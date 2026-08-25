# 记账凭证：手工凭证的增删改 + 过账/红冲/作废。
# 硬规则在 Erp::Voucher / VoucherLine / VoucherPostingService 里，控制器只做取数与状态闸。
class Api::V1::Accounts::Erp::VouchersController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_voucher, only: [:show, :update, :destroy, :post_voucher, :reverse, :void]

  def index
    scope = filtered_scope
    @vouchers_count = scope.count
    @vouchers = scope.includes(:prepared_by, :posted_by, :reversal_of)
                     .order(voucher_date: :desc, voucher_no: :desc)
                     .page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @voucher = Current.account.erp_vouchers.new(voucher_params)
    @voucher.prepared_by_id = current_user.id
    @voucher.save!
    @voucher.refresh_totals!
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def update
    return render json: { error: '已记账/已作废的凭证不能修改，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.update!(voucher_params)
    @voucher.refresh_totals!
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def destroy
    return render json: { error: '已记账的凭证不能删除，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.destroy!
    head :ok
  end

  # 过账（记账）：借贷平衡校验通过才置 POSTED。
  def post_voucher
    Erp::VoucherPostingService.new(@voucher, current_user).post!
    render 'api/v1/accounts/erp/vouchers/show'
  rescue Erp::VoucherPostingService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 红冲：生成方向相反的凭证，两张互相引用。
  def reverse
    @voucher = Erp::VoucherPostingService.new(@voucher, current_user).reverse!
    render 'api/v1/accounts/erp/vouchers/show'
  rescue Erp::VoucherPostingService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 作废：只作用于待过账凭证，留痕不删。
  def void
    return render json: { error: '已记账的凭证不能作废，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.update!(status: Erp::Voucher::VOID)
    render 'api/v1/accounts/erp/vouchers/show'
  end

  private

  def filtered_scope
    scope = Current.account.erp_vouchers
    scope = scope.where(period: params[:period]) if params[:period].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    filtered_by_date_and_keyword(scope)
  end

  def filtered_by_date_and_keyword(scope)
    date_range = Range.new(params[:from].presence, params[:to].presence) if params[:from].present? || params[:to].present?
    scope = scope.where(voucher_date: date_range) if date_range
    return scope if params[:q].blank?

    scope.where('voucher_no ILIKE :t OR summary ILIKE :t', t: "%#{params[:q].strip}%")
  end

  def fetch_voucher
    @voucher = Current.account.erp_vouchers.includes(lines: :ledger_account).find(params[:id])
  end

  def check_authorization
    authorize(Erp::Voucher)
  end

  def voucher_params
    params.require(:voucher).permit(
      :voucher_date, :summary, :remark, :attachment_count,
      lines_attributes: [
        :id, :ledger_account_id, :direction, :summary, :amount_micros, :currency, :exchange_rate, :position,
        :crm_customer_id, :mes_supplier_id, :crm_sales_order_id, :department_id, :member_id, :_destroy
      ]
    )
  end
end
