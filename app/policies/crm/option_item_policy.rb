# CRM 客户设置（分组 / 来源）：仅超级管理员与 CRM 副管理员可写（增删改/排序）；
# 读取（下拉选项）对全体登录成员开放——建档/编辑客户人人都要选分组与来源。
class Crm::OptionItemPolicy < ApplicationPolicy
  def index?
    true
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
