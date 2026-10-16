# 退料返修：MES 的人都看得到（生产要知道料什么时候回来），采购/仓管能建能登记。
class Mes::SupplierReturnPolicy < ApplicationPolicy
  def index? = @account_user.mes_staff?
  def show? = index?
  def create? = writable?
  def update? = writable?
  def destroy? = writable?
  def send_out? = writable?
  def receive_back? = writable?

  private

  # 退料退给供应商，经手的是采购或仓管。
  def writable? = @account_user.mes_can?(:purchase) || @account_user.mes_can?(:stock) || @account_user.administrator?
end

Mes::SupplierReturnPolicy.prepend_mod_with('Mes::SupplierReturnPolicy')
