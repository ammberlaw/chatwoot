# BOM 成本表（加工费/制造费用标准）：ERP 内可读，写限 cost 能力域——
# 这张表直接决定毛利里的人工与制造费用，出纳看得到、改不了。
class Erp::BomCostPolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?

  def create? = @account_user.erp_can?(:cost)
  def update? = @account_user.erp_can?(:cost)
  def destroy? = @account_user.erp_can?(:cost)
  def import? = @account_user.erp_can?(:cost)
end

Erp::BomCostPolicy.prepend_mod_with('Erp::BomCostPolicy')
