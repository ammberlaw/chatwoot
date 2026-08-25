# 付款单：付款记录 + 核销到应付台账 + 作废回滚。与收款单同构。
class Api::V1::Accounts::Erp::PaymentRecordsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payment, only: [:show, :update, :destroy, :void]

  def index
    scope = filtered_scope
    @payments_count = scope.count
    @summary = { amount_micros: scope.normal.sum(:amount_micros) }
    @payments = scope.includes(:mes_supplier, :recorded_by, allocations: :payable)
                     .order(paid_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @payment = Current.account.erp_payment_records.new(payment_params)
    @payment.recorded_by_id = current_user.id
    @payment.save!
    allocate!
    render 'api/v1/accounts/erp/payment_records/show'
  rescue Erp::AllocationService::Error => e
    @payment&.destroy
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    return render json: { error: '已作废的付款单不能修改' }, status: :unprocessable_entity unless @payment.voidable?

    @payment.update!(payment_params)
    allocate!
    render 'api/v1/accounts/erp/payment_records/show'
  rescue Erp::AllocationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def void
    Erp::AllocationService.new(@payment, :payment).void!
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
