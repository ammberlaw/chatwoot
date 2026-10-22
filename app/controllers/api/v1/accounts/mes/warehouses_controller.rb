class Api::V1::Accounts::Mes::WarehousesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_warehouse, only: [:update, :destroy]

  def index
    Mes::Warehouse.ensure_defaults!(Current.account)
    # 原来这里只放 原料仓 / 成品仓 两种出去。期初导入时建的 11 个仓（样品仓、不良品仓、
    # 四个委外仓、外贸仓…）kind 是空的，被这条过滤整个挡掉——仓库页上只剩两行，
    # 仓管以为系统里没有那些仓，而它们各自都压着真实库存（不良品仓 183 行结存）。
    # 仓库档案页要看得见自己所有的仓；哪张单该用哪个仓，是各单据选择器自己的事。
    @warehouses = Current.account.mes_warehouses.order(:position, :id)
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
