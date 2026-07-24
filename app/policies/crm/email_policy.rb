class Crm::EmailPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def counts?
    true
  end

  def mailboxes?
    true
  end

  def fetch?
    true
  end

  def attach_kb?
    true
  end

  def opens?
    true
  end

  def eml?
    true
  end

  def update?
    true
  end

  # 删除范围由控制器 visible_emails 收口（业务员仅自己、主管团队、管理员全部），
  # 故此处放开让本人可删自己的邮件（尤其草稿），不再限管理员。
  def destroy?
    true
  end
end

Crm::EmailPolicy.prepend_mod_with('Crm::EmailPolicy')
