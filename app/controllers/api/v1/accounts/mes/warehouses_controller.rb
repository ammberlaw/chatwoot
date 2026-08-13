class Api::V1::Accounts::Mes::WarehousesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_warehouse, only: [:update, :destroy]

  def index
    Mes::Warehouse.ensure_defaults!(Current.account)
    # 各出入库阶段只用 原料仓 / 成品仓 两个仓，隐藏在制品仓/废料仓。
    @warehouses = Current.account.mes_warehouses.where(kind: %w[RAW FINISHED]).order(:position, :id)
  end

  def create
    @warehouse = Current.account.mes_warehouses.create!(warehouse_params)
    render 'api/v1/accounts/mes/warehouses/show'
  end

  def update
    @warehouse.update!(warehouse_params)
    render 'api/v1/accounts/mes/warehouses/show'
  end

  def destroy
    @warehouse.destroy!
    head :ok
  end

  private

  def fetch_warehouse
    @warehouse = Current.account.mes_warehouses.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Warehouse)
  end

  def warehouse_params
    params.require(:warehouse).permit(:code, :name, :kind, :parent_id, :position, :is_active)
  end
end
