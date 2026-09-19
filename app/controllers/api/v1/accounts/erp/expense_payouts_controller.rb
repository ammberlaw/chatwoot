# 费用报销打款：承接 OA 审批通过之后的财务动作——付钱、入账、归集订单成本。
# 与收付款单同构（落库即写出纳日记账 + 生成待过账凭证；作废走反向冲销）。
class Api::V1::Accounts::Erp::ExpensePayoutsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_payout, only: [:show, :update, :void]

  # 待打款：审批通过但财务还没付钱的报销单（带金额、费用类型与建议科目）。
  def pending
    @requests = service.pending_requests
    @suggestions = @requests.to_h do |request|
      category = Erp::ExpensePayoutService.request_category(request)
      [request.id, {
        amount_micros: Erp::ExpensePayoutService.request_amount_micros(request),
        category: category,
        expense_ledger_account_id: service.default_expense_account(category)&.id
      }]
    end
  end

  def index
    scope = filtered_scope
    @payouts_count = scope.count
    @summary = { amount_micros: scope.normal.sum(:amount_micros) }
    @payouts = scope.includes(:expense_ledger_account, :cash_account, :crm_sales_order, :recorded_by,
                              approval_request: :applicant)
                    .order(paid_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    closed = closed_period_for(payout_params[:paid_at])
    return render_closed(closed, action: '打款') if closed

    @payout = service.pay!(payout_params, actor: current_user)
    render 'api/v1/accounts/erp/expense_payouts/show'
  rescue ActiveRecord::RecordNotUnique
    render json: { error: '该报销单已打过款，请刷新列表' }, status: :unprocessable_entity
  rescue Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    return render json: { error: '已作废的打款单不能修改' }, status: :unprocessable_entity unless @payout.voidable?

    # 改单会动流水/凭证/成本，原期间与新期间都不能是已结账期间。
    closed = closed_period_for(@payout.paid_at, payout_params[:paid_at])
    return render_closed(closed) if closed

    service.update_payout!(@payout, payout_params, actor: current_user)
    render 'api/v1/accounts/erp/expense_payouts/show'
  rescue Erp::AutoVoucherService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def void
    return render json: { error: '该打款单已作废' }, status: :unprocessable_entity unless @payout.voidable?

    closed = closed_period_for(@payout.paid_at)
    return render_closed(closed, action: '作废') if closed

    @posted_voucher_no = service.void!(@payout, actor: current_user)
    render 'api/v1/accounts/erp/expense_payouts/show'
  end

  private

  def filtered_scope
    scope = Current.account.erp_expense_payouts
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_sales_order_id: params[:crm_sales_order_id]) if params[:crm_sales_order_id].present?
    filtered_by_date_and_keyword(scope)
  end

  def filtered_by_date_and_keyword(scope)
    scope = scope.where(paid_at: params[:from]..) if params[:from].present?
    scope = scope.where(paid_at: ..params[:to]) if params[:to].present?
    return scope if params[:q].blank?

    scope.where('payout_no ILIKE :t OR remark ILIKE :t', t: "%#{params[:q].strip}%")
  end

  def render_closed(period, action: '修改')
    render json: { error: "该单据所属期间 #{period} 已结账，不能#{action}" }, status: :unprocessable_entity
  end

  def service
    @service ||= Erp::ExpensePayoutService.new(Current.account)
  end

  def fetch_payout
    @payout = Current.account.erp_expense_payouts.find(params[:id])
  end

  def check_authorization
    authorize(Erp::ExpensePayout)
  end

  def payout_params
    params.require(:payout).permit(
      :oa_approval_request_id, :amount_micros, :expense_ledger_account_id, :cash_account_id,
      :crm_sales_order_id, :cost_type, :paid_at, :remark
    )
  end
end
