# 定制报价模板：列表人人可读（业务员填表要用），增删改在控制器里限管理员/副管。
class Crm::QuoteRequestTemplatePolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end
end
