class Api::V1::Accounts::Mes::ProductionRecordsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = scoped_by_product_line(Current.account.mes_production_records)
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    @production_records_count = scope.count
    @production_records = scope.order(recorded_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def create
    @production_record = Current.account.mes_production_records.create!(
      production_record_params.merge(operator_id: production_record_params[:operator_id] || current_user.id)
    )
    render 'api/v1/accounts/mes/production_records/show'
  end

  def destroy
    Current.account.mes_production_records.find(params[:id]).destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(Mes::ProductionRecord)
  end

  def production_record_params
    params.require(:production_record).permit(
      :production_order_id, :operation_name, :qty_completed, :qty_returned, :qty_scrap, :operator_id, :recorded_at, :remark
    )
  end
end
