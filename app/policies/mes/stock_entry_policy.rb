class Mes::StockEntryPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  # 成品入库(MANUFACTURE)由车间(report)开单，其余 purpose 控制器里收紧到 stock。
  def create? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)
  def update? = @account_user.mes_can?(:stock) || @account_user.mes_can?(:report)
  def post? = @account_user.mes_can?(:stock)

  # 仓库清点确认（确认即过账）：仓管（stock）能力。
  def confirm_warehouse? = @account_user.mes_can?(:stock)

  def return_document? = @account_user.mes_can?(:stock)
  def reactivate? = @account_user.mes_can?(:stock)

  def destroy? = @account_user.administrator?
end

Mes::StockEntryPolicy.prepend_mod_with('Mes::StockEntryPolicy')
