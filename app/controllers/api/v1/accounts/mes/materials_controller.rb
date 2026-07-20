class Api::V1::Accounts::Mes::MaterialsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_material, only: [:show, :update, :destroy]

  def index
    scope = Current.account.mes_materials
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where(is_active: true) if params[:active] == 'true'
    scope = scope.where('name ILIKE :t OR material_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @materials_count = scope.count
    @materials = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @material = Current.account.mes_materials.create!(material_params)
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

  def material_params
    params.require(:material).permit(
      :material_no, :name, :category, :specification, :unit,
      :cost_price_micros, :currency, :safety_stock, :default_supplier_id, :is_active, :remark
    )
  end
end
