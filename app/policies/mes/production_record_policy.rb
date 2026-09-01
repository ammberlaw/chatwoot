class Mes::ProductionRecordPolicy < ApplicationPolicy
  def index? = true

  def create? = @account_user.mes_can?(:report)

  def return_document? = @account_user.mes_can?(:report)
  def reactivate? = @account_user.mes_can?(:report)

  # 报工删除（清理重复/错误报工）：报工人（车间/report 能力）即可删，与前端按钮对齐。
  def destroy? = @account_user.mes_can?(:report)
end

Mes::ProductionRecordPolicy.prepend_mod_with('Mes::ProductionRecordPolicy')
