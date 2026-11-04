# 工资表：全公司的钱都在上面，比单人薪资配置更敏感。
# 管理层恒可；另放开给财务与人事——这个功能本来就是给他们做核算用的。
class Crm::PayrollSheetPolicy < ApplicationPolicy
  def index? = payroll_access?
  def show? = payroll_access?
  def create? = payroll_access?
  def update? = payroll_access?
  def destroy? = payroll_access?
  def confirm? = payroll_access?
  def reopen? = payroll_access?
  def import? = payroll_access?
  def export? = payroll_access?

  private

  def payroll_access?
    admin_like? || account_user&.crm_finance? || account_user&.crm_hr? || false
  end

  def admin_like?
    account_user&.administrator? || account_user&.crm_deputy_admin? || false
  end
end
