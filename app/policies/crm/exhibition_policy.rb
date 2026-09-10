class Crm::ExhibitionPolicy < ApplicationPolicy
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

  def destroy?
    true
  end

  # 匹配潜客 / 加入邀约名单：候选客户按当前用户可见范围收口（控制器 visible_customers 强制）。
  def candidates?
    true
  end

  def add_invites?
    true
  end

  def apollo_search?
    true
  end

  def add_apollo_invites?
    true
  end

  def generate_sop_drafts?
    true
  end
end

Crm::ExhibitionPolicy.prepend_mod_with('Crm::ExhibitionPolicy')
