class Mes::BomPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:bom)
  def update? = @account_user.mes_can?(:bom)
  def release? = @account_user.mes_can?(:bom)
  # 图片/附件：与建单同权限。
  def stage_blob? = create?
  def attach? = update?
  def detach? = update?

  def destroy? = @account_user.administrator?
end

Mes::BomPolicy.prepend_mod_with('Mes::BomPolicy')
