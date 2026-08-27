# TikTok 出库利润表：按 店铺 × 型号 × 月份。列表按可见店铺收口；写操作按可编辑店铺把关（财务只读）。
class Api::V1::Accounts::Tiktok::ProfitRecordsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :ensure_profit_access, only: %i[index]
  before_action :fetch_record, only: %i[update destroy]

  # 利润表（含成本/毛利/净利）仅部门负责人与财务/管理层可见；普通部门成员不可查看。
  def index
    scope = profit_scope_visible(Current.account.tiktok_profit_records.includes(:shop))
    scope = scope.where(shop_id: params[:shop_id]) if params[:shop_id].present?
    scope = scope.where(stat_month: params[:month]) if params[:month].present?
    @records = scope.order(stat_month: :desc, id: :desc)
  end

  def create
    ensure_editable_shop!(record_params[:shop_id])
    return if performed?

    @record = Current.account.tiktok_profit_records.create!(record_params.merge(creator_id: Current.user&.id))
    render :show
  end

  def update
    ensure_editable_shop!(@record.shop_id)
    return if performed?

    @record.update!(record_params)
    render :show
  end

  def destroy
    ensure_editable_shop!(@record.shop_id)
    return if performed?

    @record.destroy!
    head :ok
  end

  private

  def ensure_profit_access
    return if tiktok_scope.can_view_profit?

    render json: { error: '仅部门负责人与财务可查看利润表' }, status: :forbidden
  end

  # 利润表读范围：管理层/财务全部；部门负责人限所负责部门的店铺。
  def profit_scope_visible(relation)
    ids = tiktok_scope.profit_visible_shop_ids
    ids == :all ? relation : relation.where(shop_id: ids)
  end

  def fetch_record
    @record = Current.account.tiktok_profit_records.find(params[:id])
  end

  def record_params
    params.require(:profit_record).permit(
      :shop_id, :product_model, :stat_month, :period_note, :recorded_quantity, :platform_negative,
      :recorded_amount, :currency, :cost_unit_price, :influencer_commission, :platform_commission,
      :tax, :other_cost, :other_cost_note,
      extra_expenses: [:name, :amount]
    )
  end
end
