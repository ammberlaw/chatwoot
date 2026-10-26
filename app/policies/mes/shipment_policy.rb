class Mes::ShipmentPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  # 开单：仓库（生产出库）或 CRM 业务条线（现货出库，业务员/主管/副管理员）。
  def create? = @account_user.mes_can?(:shipment) || @account_user.can_access_crm?
  def update? = create?
  # 从销售订单一键转出库单：与手工开单同一道门（业务员转自己的订单是本功能的主用法）。
  def convert? = create?
  def notify? = @account_user.mes_can?(:shipment)
  def ship? = @account_user.mes_can?(:shipment)

  # 现货出库审核：CRM 部门主管 / 副管理员 / 管理员（具体到人由控制器按 manager_id 收敛）。
  def submit? = create?
  # 自助诊断：看得到这张单就问得了。它只读，而且只回答「这张单为什么卡着、该谁动」——
  # 都是他在页面上本来就看得到的东西，不放宽任何数据面。
  def diagnose? = show?
  # ⚠️ Pundit 按 action 名找 policy 方法，少一个就是 500。
  def pending_count? = true
  # 打印计数：看得到这张单就打得了（打印本身是只读动作，计数只是留个痕）。
  def mark_printed? = true
  # 审核/驳回这道门要放仓库进来——小额单由仓库自己批（Mes::Shipment#warehouse_self_approvable?）。
  # 具体哪张单谁能批由控制器 can_approve_shipment? 按单判定，这里只管「有没有资格走到那一步」。
  def approve? = approver? || @account_user.mes_can?(:shipment)
  def reject? = approve?
  # 「出库审核」清单仍是财务那张台子，不放宽。
  def approval_inbox? = approver?

  # 退回草稿 / 作废：与删单同一道门，控制器再按状态和制单人收敛。
  def revert_to_draft? = destroy?
  def void? = destroy?

  # 删单与开单同一道门（控制器再按「草稿/被驳回」和制单人收敛）。
  # 原先只许管理员删，连制单人自己都删不掉自己的重复草稿，只能挂在列表里。
  def destroy? = create?

  private

  # 出库审核＝**财务**审「款收齐没有」（用户给的金蝶流程）。配了「出库审核人」认配的人，
  # 没配回落财务 + 管理员（副管不算，见 Mes::Shipment.approver_ids）——
  # 口径收在 Mes::Shipment.approver?，控制器也问同一个。
  def approver?
    Mes::Shipment.approver?(@account_user.account, @account_user)
  end
end

Mes::ShipmentPolicy.prepend_mod_with('Mes::ShipmentPolicy')
