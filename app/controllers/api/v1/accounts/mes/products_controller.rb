class Api::V1::Accounts::Mes::ProductsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_product, only: [:update, :destroy]

  # 产品档案（复用 CRM 产品库 Crm::Product）。MES 侧入口，供 BOM/采购/出库选成品。
  # 读全员可见；增删改仅工程与 PMC（Mes::ProductPolicy → mes_can?(:product)）。
  def index
    scope = scoped_by_product_line(Current.account.crm_products)
    scope = scope.active if params[:filter] == 'active'
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where('sku ILIKE :q OR name ILIKE :q', q: "%#{params[:q].strip}%") if params[:q].present?
    @products_count = scope.count
    @products = scope.order(updated_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

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
    authorize(Crm::Product, policy_class: Mes::ProductPolicy)
  end

  def product_params
    params.require(:product).permit(
      :name, :sku, :category, :specification, :unit, :product_line,
      :cost_price_micros, :sale_price_micros, :pricing_currency, :is_active, :remark
    )
  end
end
