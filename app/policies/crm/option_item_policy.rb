# CRM 客户设置（分组 / 来源）：仅超级管理员与 CRM 副管理员可读写（业务员/主管不可）。
class Crm::OptionItemPolicy < ApplicationPolicy
  def index?
    admin_like?
  end

  def create?
    admin_like?
  end

  def update?
    admin_like?
  end

  def destroy?
    admin_like?
  end

  def reorder?
    admin_like?
  end

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::OptionItemPolicy.prepend_mod_with('Crm::OptionItemPolicy')
