# 仅管理员可见可改（A-CRM 权限口径：销售员/主管对公海规则设置不可读写）。
class Crm::PublicPoolSettingPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end
end

Crm::PublicPoolSettingPolicy.prepend_mod_with('Crm::PublicPoolSettingPolicy')
