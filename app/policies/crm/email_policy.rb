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

  # 邮件 AI 助手（写信/翻译/摘要）：全员可用，数据范围由控制器 visible_emails 收口。
  def compose?
    true
  end

  def translate?
    true
  end

  def summarize?
    true
  end

  # 客户 AI 背调（输入邮箱→查官网）：全员可用，查库匹配由控制器按可见范围收口。
  def company_lookup?
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
