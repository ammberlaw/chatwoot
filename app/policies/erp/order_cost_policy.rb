# 成本与毛利：ERP 内可读，写限 cost 能力域（出纳看得到、改不了）。
class Erp::OrderCostPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def margin? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:cost)
  def update? = @account_user.erp_can?(:cost)
  def destroy? = @account_user.erp_can?(:cost)
end

Erp::OrderCostPolicy.prepend_mod_with('Erp::OrderCostPolicy')
