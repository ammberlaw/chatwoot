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

  # 群发单显：与建单同权限，数据范围由控制器收口。
  def bulk_create?
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

  # 会话线程：与本邮件同一往来的可见邮件（内部已按邮件可见范围收口）。
  def thread?
    true
  end

  def distribute?
    true
  end

  def distributions?
    true
  end

  def distributed?
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

  # 客户 AI 背调（输入邮箱/域名/网址→查官网+Apollo）：全员可用，查库匹配由控制器按可见范围收口。
  def company_lookup?
    true
  end

  # 按公司名搜候选公司（Apollo）：与背调同权限，全员可用。
  def company_search?
    true
  end

  def update?
    true
  end

  # 移动到文件夹：与编辑同权（数据范围由控制器 visible_emails 收口）。
  def move_to_folder?
    update?
  end

  # 删除范围由控制器 visible_emails 收口（业务员仅自己、主管团队、管理员全部），
  # 故此处放开让本人可删自己的邮件（尤其草稿），不再限管理员。
  def destroy?
    true
  end
end

Crm::EmailPolicy.prepend_mod_with('Crm::EmailPolicy')
