# TikTok 出库利润表：按 店铺 × 型号 × 月份。列表按可见店铺收口；写操作按可编辑店铺把关（财务只读）。
class Api::V1::Accounts::Tiktok::ProfitRecordsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :fetch_record, only: %i[update destroy]

  def index
    scope = scope_visible(Current.account.tiktok_profit_records.includes(:shop))
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
