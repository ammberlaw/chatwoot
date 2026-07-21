class Api::V1::Accounts::Mes::StockBalancesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = Current.account.mes_stock_balances
                   .includes(:mes_material, :crm_product, :warehouse)
                   .where('qty <> 0')
    scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    @balances = scope.to_a
    @balances = @balances.select(&:short?) if params[:short] == 'true'
  end

  private

  def check_authorization
    authorize(Mes::StockBalance)
  end
end
