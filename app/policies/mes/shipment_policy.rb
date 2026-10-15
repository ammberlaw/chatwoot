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
  # ⚠️ Pundit 按 action 名找 policy 方法，少一个就是 500。
  def pending_count? = true
  def approve? = approver?
  def reject? = approver?
  def approval_inbox? = approver?

  # 删单与开单同一道门（控制器再按「草稿/被驳回」和制单人收敛）。
  # 原先只许管理员删，连制单人自己都删不掉自己的重复草稿，只能挂在列表里。
  def destroy? = create?

  private

  # 出库审核＝**财务**审「款收齐没有」（用户给的金蝶流程）。配了「出库审核人」认配的人，
  # 没配回落财务 + 管理员/副管——口径收在 Mes::Shipment.approver?，控制器也问同一个。
  def approver?
    Mes::Shipment.approver?(@account_user.account, @account_user)
  end
end

Mes::ShipmentPolicy.prepend_mod_with('Mes::ShipmentPolicy')
