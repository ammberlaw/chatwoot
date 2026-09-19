# 付款单：付款记录 + 核销到应付台账 + 作废回滚。与收款单同构。
class Api::V1::Accounts::Erp::PaymentRecordsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payment, only: [:show, :update, :destroy, :void]

  def index
    scope = filtered_scope
    @payments_count = scope.count
    @summary = { amount_micros: scope.normal.sum(Arel.sql(Erp::PaymentRecord::BASE_AMOUNT_MICROS_SQL)) }
    @payments = scope.includes(:mes_supplier, :recorded_by, allocations: :payable)
                     .order(paid_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @payment = Current.account.erp_payment_records.new(payment_params)
    @payment.recorded_by_id = current_user.id
    ActiveRecord::Base.transaction do
      @payment.save!
      allocate!
      sync_side_effects
    end
    render 'api/v1/accounts/erp/payment_records/show'
  rescue Erp::AllocationService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    return render json: { error: '已作废的付款单不能修改' }, status: :unprocessable_entity unless @payment.voidable?

    # 与 void 同一道冻结闸：改单会动核销/台账/流水，冻结期的总账动不了（原期间与新期间都查）。
    closed = closed_period_for(@payment.paid_at, payment_params[:paid_at])
    return render json: { error: "该单据所属期间 #{closed} 已结账，不能修改" }, status: :unprocessable_entity if closed

    # 单据 / 核销 / 流水 / 自动凭证要么一起成，要么一起不动——
    # 原来任何一步抛错都会把单据留在改了一半的状态。
    ActiveRecord::Base.transaction do
      @payment.update!(payment_params)
      allocate!
      sync_side_effects
    end
    render 'api/v1/accounts/erp/payment_records/show'
  rescue Erp::AllocationService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def void
    # 已结账期间的单据不许作废(见 receipt void)：防冻结期总账↔台账永久失衡。
    period = @payment.paid_at&.to_date&.strftime('%Y-%m')
    if period && Erp::FiscalPeriod.closed?(Current.account, period)
      return render json: { error: "该单据所属期间 #{period} 已结账，不能作废" }, status: :unprocessable_entity
    end

    # 三副作用包同一事务+账套锁(见 receipt void)：整体回滚防账实分离,并发/重复作废串行化。
    Erp::AccountLock.with_account_lock(Current.account.id, "payment:#{@payment.id}") do
      Erp::AllocationService.new(@payment, :payment).void!
      Erp::CashLedgerService.new(Current.account, current_user).reverse_for(@payment)
      @posted_voucher_no = Erp::AutoVoucherService.new(Current.account).void_for(@payment)
    end
    render 'api/v1/accounts/erp/payment_records/show'
  rescue Erp::AllocationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    return render json: { error: '已核销的付款单不能删除，请作废' }, status: :unprocessable_entity if @payment.allocations.exists?

    @payment.destroy!
    head :ok
  end

  private

  # 付款单落库后：记一笔资金流出 + 生成待过账凭证。
  def sync_side_effects
    Erp::CashLedgerService.new(Current.account, current_user).sync_for(@payment, direction: Erp::CashTransaction::OUT)
    Erp::AutoVoucherService.new(Current.account).for_payment(@payment)
  end

  def allocate!
    Erp::AllocationService.new(@payment, :payment).apply!(allocation_specs)
  end

  def allocation_specs
    Array(params[:allocations]).map do |spec|
      permitted = spec.permit(:payable_id, :amount_micros)
      { ledger_id: permitted[:payable_id], amount_micros: permitted[:amount_micros] }
    end
  end

  def filtered_scope
    scope = Current.account.erp_payment_records
    scope = scope.where(mes_supplier_id: params[:mes_supplier_id]) if params[:mes_supplier_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    filtered_by_date_and_keyword(scope)
  end

  def filtered_by_date_and_keyword(scope)
    scope = scope.where(paid_at: params[:from]..) if params[:from].present?
    scope = scope.where(paid_at: ..params[:to]) if params[:to].present?
    return scope if params[:q].blank?

    scope.where('payment_no ILIKE :t OR reference_no ILIKE :t', t: "%#{params[:q].strip}%")
  end

  def fetch_payment
    @payment = Current.account.erp_payment_records.includes(allocations: :payable).find(params[:id])
  end

  def check_authorization
    authorize(Erp::PaymentRecord)
  end

  def payment_params
    params.require(:payment).permit(
      :mes_supplier_id, :cash_account_id, :amount_micros, :currency, :exchange_rate, :bank_charge_micros,
      :method, :paid_at, :reference_no, :remark
    )
  end
end
