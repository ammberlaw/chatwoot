# 定制报价申请：能进 CRM 就能提申请、能看自己相关的单。
# 具体「谁看得到哪些单、谁能报价」在控制器里按 applicant/pricer 收口（见 visible_scope / can_price?），
# 这里只做入口放行，不重复一套判断。
class Crm::QuoteRequestPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def templates?
    true
  end

  def pending_count?
    true
  end

  # 重新编辑：入口放行，是不是本人、单子是不是已撤销由控制器判断。
  def update?
    true
  end

  def quote?
    true
  end

  def transfer?
    true
  end

  def cancel?
    true
  end
end
