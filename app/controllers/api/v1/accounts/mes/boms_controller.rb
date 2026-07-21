class Api::V1::Accounts::Mes::BomsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_bom, only: [:show, :update, :destroy]

  def index
    scope = scoped_by_product_line(Current.account.mes_boms)
    scope = scope.where(crm_product_id: params[:crm_product_id]) if params[:crm_product_id].present?
    scope = scope.where('bom_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @boms_count = scope.count
    @boms = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @bom = Current.account.mes_boms.new(bom_params)
    @bom.fallback_product_line = current_product_line
    @bom.save!
    render 'api/v1/accounts/mes/boms/show'
  end

  def update
    @bom.update!(bom_params)
    render 'api/v1/accounts/mes/boms/show'
  end

  def destroy
    @bom.destroy!
    head :ok
  end

  private

  def fetch_bom
    @bom = Current.account.mes_boms.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Bom)
  end

  def bom_params
    params.require(:bom).permit(
      :crm_product_id, :base_qty, :unit, :estimated_lead_days, :is_active, :is_default, :owner_id, :remark, :product_line,
      :purchasing_days, :material_inbound_days, :picking_days, :production_days, :fg_inbound_days,
      bom_items_attributes: [:id, :mes_material_id, :material_no, :material_name, :specification, :qty, :unit, :remark, :_destroy]
    )
  end
end
