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
  # 过账这道门只放行到「有没有资格走到这一步」，真正判谁能过账在控制器
  # can_operate_entry?（要看这张单属于哪条产线、该板块的负责人是谁）。
  # 和同文件里 approve?/reject? 一个路子——policy 看不见单据，判不了产线。
  def post? = true

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

  # 删单：和 create?/update? 同一条线（stock || report）。生产岗自己开的领料单填错了
  # 得能自己删掉——以前 destroy? 只给 stock，于是「能开能改、唯独不能删」，
  # 开错一张得去求仓管（2026-10-28 生产反馈）。
  # 真正的收口在控制器：ensure_can_delete! 把非仓管的人卡到制单人本人，
  # destroy 本身又挡住已过账的单，所以生产岗最多只能硬删自己开的草稿。
  def destroy? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)

  # 作废：冲销已过账的库存流水，是仓储动作，只给仓管。
  def cancel? = @account_user.mes_can?(:stock)
end

Mes::StockEntryPolicy.prepend_mod_with('Mes::StockEntryPolicy')
