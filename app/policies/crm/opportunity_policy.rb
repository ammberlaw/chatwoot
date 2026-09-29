class Crm::OpportunityPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  # CRM 成员可删除其数据范围内的商机（业务员删自己的、主管删团队的、管理员全部）。
  # 具体范围由控制器 fetch_opportunity 的 scope_by_owner 强制，越权自然 404。
  def destroy?
    true
  end
end

Crm::OpportunityPolicy.prepend_mod_with('Crm::OpportunityPolicy')
