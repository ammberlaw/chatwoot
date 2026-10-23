class Mes::StockEntryPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  # 成品入库(MANUFACTURE)由车间(report)开单，其余 purpose 控制器里收紧到 stock。
  def create? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)

  # 收货单暂存 blob：与建单同权（原料入库前上传留证）。
  def stage_blob? = create?
  # 打印计数：看得到这张单就打得了（打印本身是只读动作，计数只是留个痕）。
  def mark_printed? = true
  def update? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)
  def post? = @account_user.mes_can?(:stock)

  # 原料↔成品转换（建单即过账）：仓管（stock）能力，同过账。
  def convert? = @account_user.mes_can?(:stock)

  # 仓库清点确认（确认即过账）：仓管（stock）能力。
  def confirm_warehouse? = @account_user.mes_can?(:stock)

  # 财务审核（通过/驳回）：审核人不是 MES 操作岗，这里只放行到「有这个页面」这一层，
  # 真正判谁能审在控制器 ensure_approver!（按「入库审核人」配置，没配回落财务/管理员）。
  def approve? = true
  def reject? = true

  def return_document? = @account_user.mes_can?(:stock)
  def reactivate? = @account_user.mes_can?(:stock)

  # 删单/作废：仓管（stock 能力，管理员含）。草稿走 destroy 硬删，已过账走 cancel 冲销退库存。
  def destroy? = @account_user.mes_can?(:stock)
  def cancel? = @account_user.mes_can?(:stock)
end

Mes::StockEntryPolicy.prepend_mod_with('Mes::StockEntryPolicy')
