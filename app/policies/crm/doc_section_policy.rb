# 资料板块：全员可读（前端渲染板块下拉），仅管理员可配置可见部门。
class Crm::DocSectionPolicy < ApplicationPolicy
  def index?
    true
  end

  def update?
    @account_user.administrator?
  end
end

Crm::DocSectionPolicy.prepend_mod_with('Crm::DocSectionPolicy')
