# 账号分组的增删改 + 配可见成员：仅管理员/副管理员。
class Crm::CredentialGroupPolicy < ApplicationPolicy
  def create? = admin_like?
  def update? = admin_like?
  def destroy? = admin_like?

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::CredentialGroupPolicy.prepend_mod_with('Crm::CredentialGroupPolicy')
