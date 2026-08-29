class Mes::PurchaseRequisitionPolicy < ApplicationPolicy
  # 请购单含建议供应商，销售端不可见（同采购单封读）；读权限收敛到 MES 人员。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?

  # 提请购 = 工程/PMC（用户定调「开发工程做采购申请单」）；bom 能力覆盖工程与 PMC。
  def create? = @account_user.mes_can?(:bom)
  def update? = @account_user.mes_can?(:bom)
  def submit? = @account_user.mes_can?(:bom)
  def cancel? = @account_user.mes_can?(:bom)

  # 转采购单 = 采购员。
  def convert? = @account_user.mes_can?(:purchase)

  def destroy? = @account_user.administrator?
end

Mes::PurchaseRequisitionPolicy.prepend_mod_with('Mes::PurchaseRequisitionPolicy')
