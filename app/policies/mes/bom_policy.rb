class Mes::BomPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  # 占用量是只读参考，与看单同权。
  def material_commitments? = true

  def create? = @account_user.mes_can?(:bom)
  def update? = @account_user.mes_can?(:bom)
  def release? = @account_user.mes_can?(:bom)
  # 图片/附件：与建单同权限。
  def stage_blob? = create?
  def attach? = update?
  def detach? = update?

  # 删单与建单同一道门，控制器再按「草稿 + 没被订单挂上 + 本人或管理员」收敛。
  # 原来只许管理员删：制单人多建了一张重复草稿自己删不掉，只能挂在列表里
  # 占着投单号，列表上同一个生产单号出现两行（2026-10-23 用户反馈）。
  def destroy? = @account_user.mes_can?(:bom) || @account_user.administrator?
end

Mes::BomPolicy.prepend_mod_with('Mes::BomPolicy')
