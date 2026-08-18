class Crm::CustomerPolicy < ApplicationPolicy
  def index?
    true
  end

  # 客户列表页顶 KPI 汇总（客户数/本月新增/在谈商机/成交订单）：可见范围收口在控制器 filtered_customers。
  def stats?
    true
  end

  # 客户详情大页：可见范围与列表一致（辖区收口在控制器 fetch_customer）。
  def detail?
    true
  end

  # 特别关注（每人各标）：任何可见该客户的 CRM 成员都能标自己的，辖区收口在 fetch_customer。
  def favorite?
    true
  end

  def unfavorite?
    true
  end

  # 仅设置「下次跟进时间」：辖区收口在控制器 fetch_customer。
  def schedule_follow_up?
    true
  end

  def check_duplicate?
    true
  end

  # 存量查重板块全员可看：撞单预防本来就要跨负责人可见（行内仅有限字段）。
  def duplicates?
    true
  end

  def dedupe_search?
    true
  end

  def identify?
    true
  end

  def churn_risk_count?
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

  # 批量导入限管理层：系统管理员 / 副管理员 / 部门主管。
  def import?
    @account_user.administrator? || @account_user.crm_deputy_admin? || @account_user.crm_manager?
  end

  def attach?
    true
  end

  def detach?
    true
  end

  # 把某来信邮箱收编为已有客户的联系人：任何 CRM 成员可操作（辖区收口在控制器 fetch_customer）。
  def attach_contact?
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
