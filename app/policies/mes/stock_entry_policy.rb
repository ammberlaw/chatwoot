class Mes::StockEntryPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:stock)
  def update? = @account_user.mes_can?(:stock)
  def post? = @account_user.mes_can?(:stock)

  def destroy? = @account_user.administrator?
end

Mes::StockEntryPolicy.prepend_mod_with('Mes::StockEntryPolicy')
