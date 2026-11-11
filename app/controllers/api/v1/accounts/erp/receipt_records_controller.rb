# 收款单：录水单 + 核销到应收台账 + 作废回滚。
class Api::V1::Accounts::Erp::ReceiptRecordsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_receipt, only: [:show, :update, :destroy, :void]

  def index
    scope = filtered_scope
    @receipts_count = scope.count
    @summary = { amount_micros: scope.normal.sum(Arel.sql(Erp::ReceiptRecord::BASE_AMOUNT_MICROS_SQL)) }
    @receipts = scope.includes(:crm_customer, :cash_account, :recorded_by, allocations: :receivable)
                     .order(received_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @receipt = Current.account.erp_receipt_records.new(receipt_params)
    @receipt.recorded_by_id = current_user.id
    ActiveRecord::Base.transaction do
      @receipt.save!
      allocate!
      sync_side_effects
    end
    render 'api/v1/accounts/erp/receipt_records/show'
  rescue Erp::AllocationService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @receipt.with_lock do
      raise Erp::AllocationService::Error, '已作废的收款单不能修改' unless @receipt.voidable?

      # 与 void 同一道冻结闸：改单会动核销/台账/流水，冻结期的总账动不了，改了就是总账↔台账永久失衡。
      # 原期间与改后的新期间都要查（把单据挪进/挪出冻结期同样不行）。
      closed = closed_period_for(@receipt.received_at, receipt_params[:received_at])
      raise Erp::AllocationService::Error, "该单据所属期间 #{closed} 已结账，不能修改" if closed

      # 单据 / 核销 / 流水 / 自动凭证要么一起成，要么一起不动——
      # 原来任何一步抛错都会把单据留在改了一半的状态。
      @receipt.update!(receipt_params)
      allocate!
      sync_side_effects
    end
    render 'api/v1/accounts/erp/receipt_records/show'
  rescue Erp::AllocationService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 作废：回滚核销与台账余额，单据留痕（已核销的单不许删，只许作废）。
  def void
    Erp::AccountLock.with_account_lock(Current.account.id, "receipt:#{@receipt.id}") do
      @receipt.with_lock do
        # 已结账期间的单据不许作废：会动已冻结的应收/资金台账却改不了已过账凭证，导致总账↔台账在冻结期永久失衡。
        period = @receipt.received_at&.to_date&.strftime('%Y-%m')
        closed = period && Erp::FiscalPeriod.closed?(Current.account, period)
        raise Erp::AllocationService::Error, "该单据所属期间 #{period} 已结账，不能作废" if closed

        # 三副作用(核销回滚+资金冲回+凭证冲销)包同一事务+账套锁：中途失败整体回滚不留账实分离，
        # 并发/重复作废被串行化(第二次进来 void! 见已作废即报错)。
        @receipt.ensure_voucher_reversed!
        Erp::AllocationService.new(@receipt, :receipt).void!
        Erp::CashLedgerService.new(Current.account, current_user).reverse_for(@receipt)
        @posted_voucher_no = Erp::AutoVoucherService.new(Current.account).void_for(@receipt)
      end
    end
    render 'api/v1/accounts/erp/receipt_records/show'
  rescue Erp::AllocationService::Error, Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    return render json: { error: '已核销的收款单不能删除，请作废' }, status: :unprocessable_entity if @receipt.allocations.exists?

    if @receipt.destroy
      head :ok
    else
      render json: { error: @receipt.errors.full_messages.join('；') }, status: :unprocessable_entity
    end
  end

  private

  # 收款单落库后的两件事：记一笔资金流入 + 生成待过账凭证（财务审一眼即可）。
  def sync_side_effects
    Erp::CashLedgerService.new(Current.account, current_user).sync_for(@receipt, direction: Erp::CashTransaction::IN)
    Erp::AutoVoucherService.new(Current.account).for_receipt(@receipt)
  end

  def allocate!
    Erp::AllocationService.new(@receipt, :receipt).apply!(allocation_specs)
  end

  def allocation_specs
    Array(params[:allocations]).map do |spec|
      permitted = spec.permit(:receivable_id, :amount_micros)
      { ledger_id: permitted[:receivable_id], amount_micros: permitted[:amount_micros] }
    end
  end

  # 表头漏斗能筛哪几列（列名 → SQL）。与列表上看到的那几列一一对应。
  COLUMN_SQL = {
    'no' => 'erp_receipt_records.receipt_no',
    'customer' => 'crm_customers.name',
    'method' => 'erp_receipt_records.method',
    'reference' => 'erp_receipt_records.reference_no',
    'status' => 'erp_receipt_records.status'
  }.freeze

  def filtered_scope
    scope = Current.account.erp_receipt_records
    scope = scope.where(crm_customer_id: params[:crm_customer_id]) if params[:crm_customer_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = filtered_by_date_and_keyword(scope)
    return scope if params[:cf].blank?

    # 客户名在关联表上，有筛才 join。
    apply_column_filters(scope.left_joins(:crm_customer), COLUMN_SQL)
  end

  def filtered_by_date_and_keyword(scope)
    scope = scope.where(received_at: params[:from]..) if params[:from].present?
    scope = scope.where(received_at: ..params[:to]) if params[:to].present?
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.where('receipt_no ILIKE :t OR reference_no ILIKE :t', t: term)
  end

  def fetch_receipt
    @receipt = Current.account.erp_receipt_records.includes(:cash_account, allocations: :receivable).find(params[:id])
  end

  def check_authorization
    authorize(Erp::ReceiptRecord)
  end

  def receipt_params
    params.require(:receipt).permit(
      :crm_customer_id, :cash_account_id, :amount_micros, :currency, :exchange_rate, :bank_charge_micros,
      :method, :received_at, :reference_no, :trade_assurance_no, :remark
    )
  end
end
