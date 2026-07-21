class Mes::ProductionOrderPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def requirement? = true

  def create? = @account_user.mes_can?(:order)
  def convert? = @account_user.mes_can?(:order)
  # 挂 BOM / 下发采购：工程 + PMC（order 或 bom 能力）。
  def attach_bom? = @account_user.mes_can?(:order) || @account_user.mes_can?(:bom)
  def release_purchasing? = attach_bom?
  def update? = @account_user.mes_can?(:order)

  def destroy? = @account_user.administrator?
end

Mes::ProductionOrderPolicy.prepend_mod_with('Mes::ProductionOrderPolicy')
