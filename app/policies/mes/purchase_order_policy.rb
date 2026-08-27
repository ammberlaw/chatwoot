class Mes::PurchaseOrderPolicy < ApplicationPolicy
  # 明细挂供应商、单头有采购金额，销售端不可见（生态硬约束）；
  # 业务员看生产进度走生产订单阶段名，不需要读采购单。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?
  def requirement? = @account_user.mes_staff?
  # 按供应商拆单导出（发供应商用），与查看同权。
  def export? = @account_user.mes_staff?
  def export_data? = @account_user.mes_staff?

  def create? = @account_user.mes_can?(:purchase)
  def update? = @account_user.mes_can?(:purchase)

  def return_document? = @account_user.mes_can?(:purchase)
  def reactivate? = @account_user.mes_can?(:purchase)

  def destroy? = @account_user.administrator?
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
