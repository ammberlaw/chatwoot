class Erp::FiscalPeriodPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def opening_balance? = @account_user.can_access_erp?
  def reconciliation? = @account_user.can_access_erp?
  def revaluation? = @account_user.can_access_erp?
  def revalue? = @account_user.erp_can?(:close)
  def save_opening_balance? = @account_user.erp_can?(:close)

  # 结账是会计动作，限 close 能力域；反结账在控制器里另外卡管理员。
  def close? = @account_user.erp_can?(:close)
  def reopen? = @account_user.erp_can?(:close)
end

Erp::FiscalPeriodPolicy.prepend_mod_with('Erp::FiscalPeriodPolicy')
