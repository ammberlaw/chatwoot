class Api::V1::Accounts::Mes::MaterialPricesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_material_price, only: [:update, :destroy]

  # 列表：按物料编码/名称/规格搜。名称与规格从商品档带，不在本表存副本。
  def index
    scope = Current.account.mes_material_prices.includes(:crm_product, :updated_by).joins(:crm_product)
    if params[:q].present?
      scope = scope.where(
        'crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t',
        t: "%#{params[:q].strip}%"
      )
    end
    @material_prices_count = scope.count
    @material_prices = scope.order('crm_products.sku').page(page_param).per(per_page_param)
  end

  def create
    @material_price = Current.account.mes_material_prices.new(material_price_params.merge(updated_by: current_user))
    @material_price.save!
    render 'api/v1/accounts/mes/material_prices/show'
  end

  def update
    @material_price.update!(material_price_params.except(:crm_product_id).merge(updated_by: current_user))
    render 'api/v1/accounts/mes/material_prices/show'
  end

  def destroy
    @material_price.destroy!
    head :ok
  end

  # Excel 批量导入（物料编码 / 单价）。财务那边的现有单价表贴进来就行，
  # 对不上商品档的行整行退回并列出来，不自动建档。
  def import
    return render json: { error: '请选择要导入的 Excel 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Mes::MaterialPriceImportService.new(account: Current.account, user: current_user,
                                                 path: params[:file].tempfile.path).import!
    render json: { payload: result }
  rescue Mes::MaterialPriceImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 缺价清单：生产任务单用到、但本表和采购单都没有价的物料。
  # 给采购/财务当补录工作单，比「覆盖率 17%」这种数字有用。
  def missing
    @missing = Mes::MissingPriceFinder.new(account: Current.account).perform
    render 'api/v1/accounts/mes/material_prices/missing'
  end

  private

  def fetch_material_price
    @material_price = Current.account.mes_material_prices.find(params[:id])
  end

  def check_authorization
    authorize(Mes::MaterialPrice)
  end

  def per_page_param
    n = params[:per_page].to_i
    n.positive? ? [n, 500].min : 25
  end

  def material_price_params
    params.require(:material_price).permit(:crm_product_id, :unit_price_micros, :remark)
  end
end
