class Api::V1::Accounts::Mes::InspectionsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = Current.account.mes_inspections
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    scope = scope.where(result: params[:result]) if params[:result].present?
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    @inspections_count = scope.count
    @inspections = scope.order(inspected_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def create
    @inspection = Current.account.mes_inspections.create!(
      inspection_params.merge(inspector_id: inspection_params[:inspector_id] || current_user.id)
    )
    render 'api/v1/accounts/mes/inspections/show'
  end

  def destroy
    Current.account.mes_inspections.find(params[:id]).destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(Mes::Inspection)
  end

  def inspection_params
    params.require(:inspection).permit(
      :kind, :item_type, :mes_material_id, :crm_product_id, :production_order_id, :purchase_order_id,
      :inspected_qty, :passed_qty, :failed_qty, :result, :defect_reason, :need_rework, :inspector_id, :inspected_at, :remark
    )
  end
end
