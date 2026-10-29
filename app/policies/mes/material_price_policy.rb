# 物料标准单价表。含成本，口径与生产任务单上的单价列一致：
# 只给财务 / 管理员 / 采购看（Amber 2026-10-10 定）。
# 写入限采购能力域与财务——这张表是成本核算的基准，工程/生产改不得。
class Mes::MaterialPricePolicy < ApplicationPolicy
  def index? = @account_user.can_view_material_cost?
  def show? = @account_user.can_view_material_cost?
  # 缺价清单：能看成本的都能看（采购据此补录，财务据此判断合计可信度）
  def missing? = @account_user.can_view_material_cost?

  def create? = writable?
  def update? = writable?
  def destroy? = writable?
  def import? = writable?
  # 从历史采购单回填：只填空缺、不覆盖已维护的价，和手工录入同一个口子
  def backfill_from_purchases? = writable?

  private

  def writable?
    @account_user.crm_finance? || @account_user.crm_deputy_admin? || @account_user.mes_can?(:purchase)
  end
end

Mes::MaterialPricePolicy.prepend_mod_with('Mes::MaterialPricePolicy')
