class Mes::SupplierPolicy < ApplicationPolicy
  # 含采购单价/税号银行资料，**销售端**不可见（生态硬约束）。
  # 财务只读：按供应商对账是本职（应付台账、采购单上本来就看得到供应商名），
  # 挡着等于让她在采购单和供应商档案之间来回猜。建档/改档仍要 master 能力。
  def index? = readable?
  def show? = readable?

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?

  private

  def readable? = @account_user.mes_staff? || @account_user.crm_finance?
end

Mes::SupplierPolicy.prepend_mod_with('Mes::SupplierPolicy')
