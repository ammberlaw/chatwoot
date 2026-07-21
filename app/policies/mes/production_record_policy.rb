class Mes::ProductionRecordPolicy < ApplicationPolicy
  def index? = true

  def create? = @account_user.mes_can?(:report)

  def destroy? = @account_user.administrator?
end

Mes::ProductionRecordPolicy.prepend_mod_with('Mes::ProductionRecordPolicy')
