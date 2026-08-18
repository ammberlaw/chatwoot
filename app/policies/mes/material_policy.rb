class Mes::MaterialPolicy < ApplicationPolicy
  # 物料主数据含成本价(cost_price)与默认供应商，销售端不可见（生态硬约束），
  # 仅 MES 操作岗与管理员可读（与 供应商/采购单 policy 同口径）。物料仅 MES 岗页面使用。
  def index? = @account_user.mes_staff?
  def show? = @account_user.mes_staff?

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?
end

Mes::MaterialPolicy.prepend_mod_with('Mes::MaterialPolicy')
