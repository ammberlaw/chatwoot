class Mes::InspectionPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:quality)

  # 质检报告暂存 blob：与建单同权。
  def stage_blob? = create?

  def destroy? = @account_user.administrator?
end

Mes::InspectionPolicy.prepend_mod_with('Mes::InspectionPolicy')
