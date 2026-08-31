class Mes::StockEntryPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  # 成品入库(MANUFACTURE)由车间(report)开单，其余 purpose 控制器里收紧到 stock。
  def create? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)

  # 收货单暂存 blob：与建单同权（原料入库前上传留证）。
  def stage_blob? = create?
  def update? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)
  def post? = @account_user.mes_can?(:stock)

  # 仓库清点确认（确认即过账）：仓管（stock）能力。
  def confirm_warehouse? = @account_user.mes_can?(:stock)

  def return_document? = @account_user.mes_can?(:stock)
  def reactivate? = @account_user.mes_can?(:stock)

  # 删单/作废：仓管（stock 能力，管理员含）。草稿走 destroy 硬删，已过账走 cancel 冲销退库存。
  def destroy? = @account_user.mes_can?(:stock)
  def cancel? = @account_user.mes_can?(:stock)
end

Mes::StockEntryPolicy.prepend_mod_with('Mes::StockEntryPolicy')
