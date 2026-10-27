# 考核表：人人可访问（数据范围与操作权在控制器按角色/审批人控制）。撤回下发=删，见 destroy?。
class Crm::KpiSheetPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def update? = true
  def submit? = true
  def score? = true
  def hr_confirm? = true
  def gm_confirm? = true
  def ai_suggest? = true
  def return_sheet? = true
  def reopen_scoring? = true

  # 侧栏角标：谁都能问「等我填/打分几张」，数本身已按 KpiReminderJob.actionable_for 收口。
  # ⚠️ Pundit 按动作名找 policy 方法，少一个就是 500——这条角标接口上线时漏了这里，
  # 每个人一打开页面侧栏就撞一次（2026-10-27 生产实证）。新增 collection 动作必须同步加。
  def pending_count? = true

  # 撤回下发（删除考核表）：管理员/副管理员/主管可发起；具体「仅待填报 + 主管限本部门」在控制器守卫。
  def destroy?
    @account_user.administrator? || @account_user.crm_deputy_admin? || @account_user.crm_manager?
  end
end

Crm::KpiSheetPolicy.prepend_mod_with('Crm::KpiSheetPolicy')
