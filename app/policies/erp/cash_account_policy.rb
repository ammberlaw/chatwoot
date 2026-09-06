class Erp::CashAccountPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?
  def transactions? = @account_user.can_access_erp?

  # 资金账户与划转是出纳的活：cash 能力域（财务与出纳都有）。
  def create? = @account_user.erp_can?(:cash)
  def update? = @account_user.erp_can?(:cash)
  def destroy? = @account_user.erp_can?(:cash)
  def transfer? = @account_user.erp_can?(:cash)
end

Erp::CashAccountPolicy.prepend_mod_with('Erp::CashAccountPolicy')
