# 订单成本归集与毛利报表。成本/毛利是权限墙核心区，只在 ERP 内可见。
class Api::V1::Accounts::Erp::OrderCostsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_cost, only: [:update, :destroy]

  def index
    scope = Current.account.erp_order_costs.includes(:crm_sales_order, :mes_supplier, :created_by)
    scope = scope.where(crm_sales_order_id: params[:crm_sales_order_id]) if params[:crm_sales_order_id].present?
    scope = scope.where(cost_type: params[:cost_type]) if params[:cost_type].present?
    # 原来是 limit(200) 写死、前端也不翻页。成本行是**自动归集**出来的
    # （一张自产生产订单就产材料/人工/制造费用三行），量只会越滚越多，
    # 超出的部分在界面上直接消失、还看不出被截断了。
    @costs_count = scope.count
    @costs = scope.order(created_at: :desc).page(page_param).per(per_page_param)
  end

  def create
    @cost = Current.account.erp_order_costs.new(cost_params)
    @cost.created_by_id = current_user.id
    @cost.save!
    render 'api/v1/accounts/erp/order_costs/show'
  end

  def update
    @cost.update!(cost_params)
    render 'api/v1/accounts/erp/order_costs/show'
  end

  def destroy
    @cost.destroy!
    head :ok
  end

  # 一键归集：把 MES 的领料/外协采购算成成本行（补历史用；日常由生产订单出货时自动触发）。
  # 幂等——重复点只更新金额，不会翻倍；手工录入的行不受影响。
  def rollup
    @result = Erp::CostRollupService.new(Current.account).rollup_all(from: params[:from], to: params[:to])
    render json: { payload: @result }
  end

  # 毛利报表：订单维度 + 业务员/客户汇总。合计/汇总按全量算，明细超 200 行截断并打标。
  DETAIL_LIMIT = 200
  # 导出要的是整张表，不是屏幕上那 200 行；上限仍留着，免得一次拉爆内存（超了照样打 truncated）。
  EXPORT_DETAIL_LIMIT = 5_000

  def margin
    @summary_by = params[:group_by].presence
    report = Erp::MarginService.new(Current.account)
                               .report(from: params[:from], to: params[:to], group_by: @summary_by,
                                       limit: detail_limit)
    @rows = report[:rows]
    @summary = report[:summary]
    @totals = report[:totals]
    @truncated = report[:truncated]
    @total_count = report[:total_count]
    # 按 0 计价的料：成本少算了但不报错，毛利只是悄悄偏高。摆出来才查得到。
    @unpriced = Erp::UnpricedIssueFinder.new(Current.account).perform(from: params[:from], to: params[:to])
    render 'api/v1/accounts/erp/order_costs/margin'
  end

  private

  # 默认 200 行够看；带 limit 的（导出）放宽到 5000 封顶。
  def detail_limit
    requested = params[:limit].to_i
    return DETAIL_LIMIT unless requested.positive?

    [requested, EXPORT_DETAIL_LIMIT].min
  end

  def fetch_cost
    @cost = Current.account.erp_order_costs.find(params[:id])
  end

  def check_authorization
    authorize(Erp::OrderCost)
  end

  def cost_params
    params.require(:order_cost).permit(
      :crm_sales_order_id, :cost_type, :amount_micros, :currency, :exchange_rate,
      :happened_at, :mes_supplier_id, :remark
    )
  end
end
