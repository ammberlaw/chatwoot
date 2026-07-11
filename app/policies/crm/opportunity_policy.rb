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

  # 仅管理员可删除。S3 阶段引入销售/主管自定义角色后再细化。
  def destroy?
    @account_user.administrator?
  end
end

Crm::OpportunityPolicy.prepend_mod_with('Crm::OpportunityPolicy')
