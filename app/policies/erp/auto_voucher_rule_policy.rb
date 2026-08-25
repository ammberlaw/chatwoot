# 自动凭证规则改的是记账科目映射，归 ledger 能力域（出纳不可改）。
class Erp::AutoVoucherRulePolicy < ApplicationPolicy
  def index? = @account_user.can_access_erp?
  def update? = @account_user.erp_can?(:ledger)
end

Erp::AutoVoucherRulePolicy.prepend_mod_with('Erp::AutoVoucherRulePolicy')
