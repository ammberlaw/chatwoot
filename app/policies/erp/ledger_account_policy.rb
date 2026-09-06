class Erp::LedgerAccountPolicy < ApplicationPolicy
  # 读：能进 ERP 的成员即可（基类 ensure_erp_access 已挡掉销售端）。
  def index? = @account_user.can_access_erp?
  def show? = @account_user.can_access_erp?

  # 写：科目表是记账地基，限 ledger 能力域（财务/管理员/副管理员）。出纳不可改。
  def create? = @account_user.erp_can?(:ledger)
  def update? = @account_user.erp_can?(:ledger)
  def initialize_standard? = @account_user.erp_can?(:ledger)

  def destroy? = @account_user.erp_can?(:ledger)
end

Erp::LedgerAccountPolicy.prepend_mod_with('Erp::LedgerAccountPolicy')
