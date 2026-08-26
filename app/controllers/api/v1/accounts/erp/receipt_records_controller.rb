# 收款单：录水单 + 核销到应收台账 + 作废回滚。
class Api::V1::Accounts::Erp::ReceiptRecordsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_receipt, only: [:show, :update, :destroy, :void]

  def index
    scope = filtered_scope
    @receipts_count = scope.count
    @summary = { amount_micros: scope.normal.sum(:amount_micros) }
    @receipts = scope.includes(:crm_customer, :recorded_by, allocations: :receivable)
                     .order(received_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
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
    return render json: { error: '已作废的收款单不能修改' }, status: :unprocessable_entity unless @receipt.voidable?

    # 单据 / 核销 / 流水 / 自动凭证要么一起成，要么一起不动——
    # 原来任何一步抛错都会把单据留在改了一半的状态。
    ActiveRecord::Base.transaction do
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
    Erp::AllocationService.new(@receipt, :receipt).void!
    Erp::CashLedgerService.new(Current.account, current_user).reverse_for(@receipt)
    @posted_voucher_no = Erp::AutoVoucherService.new(Current.account).void_for(@receipt)
    render 'api/v1/accounts/erp/receipt_records/show'
  rescue Erp::AllocationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    return render json: { error: '已核销的收款单不能删除，请作废' }, status: :unprocessable_entity if @receipt.allocations.exists?

    @receipt.destroy!
    head :ok
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

  def filtered_scope
    scope = Current.account.erp_receipt_records
    scope = scope.where(crm_customer_id: params[:crm_customer_id]) if params[:crm_customer_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    filtered_by_date_and_keyword(scope)
  end

  def filtered_by_date_and_keyword(scope)
    scope = scope.where(received_at: params[:from]..) if params[:from].present?
    scope = scope.where(received_at: ..params[:to]) if params[:to].present?
    return scope if params[:q].blank?

    term = "%#{params[:q].strip}%"
    scope.where('receipt_no ILIKE :t OR reference_no ILIKE :t', t: term)
  end

  def fetch_receipt
    @receipt = Current.account.erp_receipt_records.includes(allocations: :receivable).find(params[:id])
  end

  def check_authorization
    authorize(Erp::ReceiptRecord)
  end

  def receipt_params
    params.require(:receipt).permit(
      :crm_customer_id, :cash_account_id, :amount_micros, :currency, :exchange_rate, :bank_charge_micros,
      :method, :received_at, :reference_no, :remark
    )
  end
end
