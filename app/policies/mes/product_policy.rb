class Mes::ProductPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  # 商品类别树：和列表同权限（全员可读）。
  def categories? = true

  # 产品档案/编码仅工程与 PMC（及管理员/副管理员）可增删改。
  def create? = @account_user.mes_can?(:product)
  def update? = @account_user.mes_can?(:product)
  def destroy? = @account_user.mes_can?(:product)
end

Mes::ProductPolicy.prepend_mod_with('Mes::ProductPolicy')
