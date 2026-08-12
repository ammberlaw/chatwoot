# TikTok 店铺：录入下拉数据源。列表按可见范围收口；增删改+部门归属仅管理员/副管理员。
class Api::V1::Accounts::Tiktok::ShopsController < Api::V1::Accounts::Tiktok::BaseController
  before_action :ensure_manage, only: %i[create update destroy]
  before_action :fetch_shop, only: %i[update destroy]

  def index
    Tiktok::Shop.ensure_defaults!(Current.account) if tiktok_scope.can_manage?
    # 店铺表自身主键是 id（无 shop_id 列），不能用按 shop_id 收口的 scope_visible，否则非管理员查询报错。
    scope = Current.account.tiktok_shops.includes(:department)
    ids = tiktok_scope.visible_shop_ids
    @shops = (ids == :all ? scope : scope.where(id: ids)).ordered
  end

  def create
    @shop = Current.account.tiktok_shops.create!(shop_params.merge(position: next_position))
    render :show
  end

  def update
    @shop.update!(shop_params)
    render :show
  end

  # 有历史销售/利润记录的店铺禁止删除，提示改为停用。
  def destroy
    if @shop.daily_sales_records.exists? || @shop.profit_records.exists?
      return render json: { error: '该店铺已有数据，请改为「停用」而非删除' }, status: :unprocessable_entity
    end

    @shop.destroy!
    head :ok
  end

  private

  def fetch_shop
    @shop = Current.account.tiktok_shops.find(params[:id])
  end

  def next_position
    (Current.account.tiktok_shops.maximum(:position) || -1) + 1
  end

  def shop_params
    params.require(:shop).permit(:name, :region, :active, :department_id)
  end
end
