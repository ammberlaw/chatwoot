class Mes::BomTemplatePolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:bom)
  def update? = @account_user.mes_can?(:bom)
  def destroy? = @account_user.mes_can?(:bom)
end

Mes::BomTemplatePolicy.prepend_mod_with('Mes::BomTemplatePolicy')
