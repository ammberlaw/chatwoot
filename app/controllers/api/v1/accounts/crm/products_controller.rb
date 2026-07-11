class Api::V1::Accounts::Crm::ProductsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_product, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 15

  def index
    @products_scope = filtered_products
    @products_count = @products_scope.count
    @products = @products_scope
                .order(updated_at: :desc)
                .page(permitted_params[:page] || 1)
                .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @product = Current.account.crm_products.create!(product_params)
  end

  def update
    @product.update!(product_params)
  end

  def destroy
    @product.destroy!
    head :ok
  end

  private

  def fetch_product
    @product = Current.account.crm_products.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Product)
  end

  # 视图筛选：在售产品(active)、按分类、按 SKU/名称搜索。
  def filtered_products
    scope = Current.account.crm_products
    scope = scope.active if params[:filter] == 'active'
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('sku ILIKE :q OR name ILIKE :q', q: "%#{params[:q]}%") if params[:q].present?
    scope
  end

  def product_params
    params.require(:product).permit(
      :name, :sku, :category, :specification, :unit,
      :cost_price_micros, :sale_price_micros, :pricing_currency, :is_active, :remark
    )
  end

  def permitted_params
    params.permit(:page, :filter, :category, :q)
  end
end
