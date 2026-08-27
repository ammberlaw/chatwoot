class Mes::ProductGroupPolicy < ApplicationPolicy
  # 分组树读全员可见（侧栏筛选 + 产品表单选分组）；维护限工程与 PMC（及管理员/副管理员），
  # 与产品档案增删改同口径（Mes::ProductPolicy）。
  def index? = true

  def create? = @account_user.mes_can?(:product)
  def update? = @account_user.mes_can?(:product)
  def destroy? = @account_user.mes_can?(:product)
  def reorder? = @account_user.mes_can?(:product)
end

Mes::ProductGroupPolicy.prepend_mod_with('Mes::ProductGroupPolicy')
