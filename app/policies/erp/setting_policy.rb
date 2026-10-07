class Erp::SettingPolicy < ApplicationPolicy
  # 读：能进 ERP 的成员即可（税率/含税口径是看单据时要对照的）。
  def show? = @account_user.can_access_erp?

  # 写：会计政策（启用日/税率/含税/台账开关）限 ledger 能力域——财务与管理员，出纳不可改。
  def update? = @account_user.erp_can?(:ledger)
end

Erp::SettingPolicy.prepend_mod_with('Erp::SettingPolicy')
