class Api::V1::Accounts::Mes::MaterialsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_material, only: [:show, :update, :destroy]

  # category=仓别（原料/半成品/成品…），item_category=采购品类（包材/主板/外壳…），两个维度各筛各的。
  COLUMN_FILTERS = { category: :category, item_category: :item_category }.freeze

  def index
    scope = filtered_materials
    @materials_count = scope.count
    @materials = scope.order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @material = Current.account.mes_materials.new(material_params)
    @material.fallback_product_line = current_product_line
    @material.save!
    render 'api/v1/accounts/mes/materials/show'
  end

  def update
    @material.update!(material_params)
    render 'api/v1/accounts/mes/materials/show'
  end

  def destroy
    @material.destroy!
    head :ok
  end

  private

  def fetch_material
    @material = Current.account.mes_materials.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Material)
  end

  def filtered_materials
    scope = scoped_by_product_line(Current.account.mes_materials)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = scope.where(is_active: true) if params[:active] == 'true'
    return scope if params[:q].blank?

    scope.where('name ILIKE :t OR material_no ILIKE :t', t: "%#{params[:q].strip}%")
  end

  def material_params
    params.require(:material).permit(
      :material_no, :name, :category, :item_category, :specification, :unit, :product_line,
      :base_no, :cost_price_micros, :currency, :safety_stock, :default_supplier_id, :is_active, :remark,
      attrs: {}
    )
  end
end
