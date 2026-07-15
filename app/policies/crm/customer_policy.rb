class Crm::CustomerPolicy < ApplicationPolicy
  def index?
    true
  end

  def check_duplicate?
    true
  end

  def claim?
    true
  end

  def release?
    true
  end

  # 批量转移：角色与范围校验在控制器（reassign_allowed? + 辖区收口）。
  def reassign?
    true
  end

  def attach?
    true
  end

  def detach?
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

  # 仅管理员可删除客户。后续 S3 阶段引入「销售/销售主管」自定义角色后再细化。
  def destroy?
    @account_user.administrator?
  end
end

Crm::CustomerPolicy.prepend_mod_with('Crm::CustomerPolicy')
