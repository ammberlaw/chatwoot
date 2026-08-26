# TikTok 每日销售录入：一店一天一行。列表按可见店铺收口；写操作按可编辑店铺把关（财务只读）。
class Api::V1::Accounts::Tiktok::SalesRecordsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :fetch_record, only: %i[update destroy]

  def index
    scope = scope_visible(Current.account.tiktok_daily_sales_records.includes(:shop))
    scope = scope.where(shop_id: params[:shop_id]) if params[:shop_id].present?
    scope = filter_by_month(scope)
    @records = scope.order(sale_date: :desc, id: :desc)
  end

  def create
    ensure_editable_shop!(record_params[:shop_id])
    return if performed?

    @record = Current.account.tiktok_daily_sales_records.create!(record_params.merge(creator_id: Current.user&.id))
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

  def filter_by_month(scope)
    return scope if params[:month].blank?

    start_date = Date.strptime(params[:month], '%Y-%m')
    scope.where(sale_date: start_date..start_date.end_of_month)
  rescue ArgumentError
    scope
  end

  def fetch_record
    @record = Current.account.tiktok_daily_sales_records.find(params[:id])
  end

  def record_params
    params.require(:sales_record).permit(
      :sale_date, :shop_id, :total_orders, :total_units, :sales_amount, :currency,
      :cancelled_units, :shipped_units, :influencer_units, :remark,
      :alliance_live_orders, :alliance_orders, :product_card_orders, :merchant_orders
    )
  end
end
