class Mes::ShipmentPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  # 开单：仓库（生产出库）或 CRM 业务条线（现货出库，业务员/主管/副管理员）。
  def create? = @account_user.mes_can?(:shipment) || @account_user.can_access_crm?
  def update? = create?
  def notify? = @account_user.mes_can?(:shipment)
  def ship? = @account_user.mes_can?(:shipment)

  # 现货出库审核：CRM 部门主管 / 副管理员 / 管理员（具体到人由控制器按 manager_id 收敛）。
  def submit? = create?
  def approve? = approver?
  def reject? = approver?
  def approval_inbox? = approver?

  def destroy? = @account_user.administrator?

  private

  def approver?
    @account_user.administrator? || @account_user.crm_deputy_admin? || @account_user.crm_manager?
  end
end

Mes::ShipmentPolicy.prepend_mod_with('Mes::ShipmentPolicy')
