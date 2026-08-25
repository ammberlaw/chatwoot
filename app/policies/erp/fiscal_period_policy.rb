class Erp::FiscalPeriodPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?

  # 结账是会计动作，限 close 能力域；反结账在控制器里另外卡管理员。
  def close? = @account_user.erp_can?(:close)
  def reopen? = @account_user.erp_can?(:close)
end

Erp::FiscalPeriodPolicy.prepend_mod_with('Erp::FiscalPeriodPolicy')
