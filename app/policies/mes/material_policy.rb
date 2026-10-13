class Mes::MaterialPolicy < ApplicationPolicy
  # 物料主数据含成本价(cost_price)与默认供应商，**销售端**不可见（生态硬约束）。
  # 财务只读：她本来就能看物料成本和物料单价表，挡着主数据只会让那些页面报 403
  # （与 供应商/采购单 policy 同口径）。建档/改档仍要 master 能力。
  def index? = readable?
  def show? = readable?

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?

  private

  def readable? = @account_user.mes_staff? || @account_user.crm_finance?
end

Mes::MaterialPolicy.prepend_mod_with('Mes::MaterialPolicy')
