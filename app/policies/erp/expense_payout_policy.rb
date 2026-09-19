# 报销审核打款：claim 能力域（财务有，出纳没有——出纳只管收付款与资金）。
class Erp::ExpensePayoutPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?
  def pending? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:claim)
  def update? = @account_user.erp_can?(:claim)
  def void? = @account_user.erp_can?(:claim)
end

Erp::ExpensePayoutPolicy.prepend_mod_with('Erp::ExpensePayoutPolicy')
