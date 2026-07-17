# 考核方案：人人可读（销售员透明看本月标准）；增改删仅管理员/主管。
class Crm::KpiSchemePolicy < ApplicationPolicy
  def index?
    scheme_visible?
  end

  def show?
    scheme_visible?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  def distribute?
    manage?
  end

  private

  def manage?
    @account_user.administrator? || Current.account_user&.crm_deputy_admin? ||
      Current.account_user&.crm_hr? || Current.account_user&.crm_manager?
  end

  # 按角色可见性（业务员/主管开关；管理员始终可见）。
  def scheme_visible?
    Crm::PerformanceSetting.scheme_visible?(@account_user.account.crm_performance_setting, @account_user)
  end
end

Crm::KpiSchemePolicy.prepend_mod_with('Crm::KpiSchemePolicy')
