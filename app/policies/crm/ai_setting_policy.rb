# 邮件 AI 设置：仅超级管理员与管理员（deputy_admin）可见可改（业务员/主管不可读写）。
class Crm::AiSettingPolicy < ApplicationPolicy
  def show?
    admin_like?
  end

  def update?
    admin_like?
  end

  def test?
    admin_like?
  end

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::AiSettingPolicy.prepend_mod_with('Crm::AiSettingPolicy')
