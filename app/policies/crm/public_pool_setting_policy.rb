# 公海规则：仅超级管理员与管理员（deputy_admin）可见可改（业务员/部门负责人不可读写）。
class Crm::PublicPoolSettingPolicy < ApplicationPolicy
  def show?
    admin_like?
  end

  def update?
    admin_like?
  end

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::PublicPoolSettingPolicy.prepend_mod_with('Crm::PublicPoolSettingPolicy')
