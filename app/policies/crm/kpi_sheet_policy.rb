# 考核表：人人可访问（数据范围与操作权在控制器按角色/审批人控制）。删仅管理员。
class Crm::KpiSheetPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def update? = true
  def submit? = true
  def score? = true
  def hr_confirm? = true
  def gm_confirm? = true

  def destroy?
    @account_user.administrator?
  end
end

Crm::KpiSheetPolicy.prepend_mod_with('Crm::KpiSheetPolicy')
