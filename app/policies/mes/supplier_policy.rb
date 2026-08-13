class Mes::SupplierPolicy < ApplicationPolicy
  # 含采购单价/税号银行资料，销售端不可见（生态硬约束），仅 MES 操作岗与管理员可读。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?
end

Mes::SupplierPolicy.prepend_mod_with('Mes::SupplierPolicy')
