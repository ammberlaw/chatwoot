# 委外加工：MES 的人都看得到（生产要知道这批货在哪家厂、什么时候回来）。
#
# 谁能安排委外＝**工程 / PMC**（用户 2026-11-02 定）。外发哪一单、发给哪家厂、
# 什么时候要回来，是排产决策，跟着生产任务单走——`:bom` 能力域正好圈出 pmc
# 与 engineer 两个岗位，采购/仓管/生产都不在内。
#
# 发料/入库/退料是仓管的手上活（料真的要出入仓），单独按 `:stock` 放行；
# 挂加工费＝起应付账，是财务的活（与应付台账「先对账再建账」同口径）。
class Mes::OutsourceOrderPolicy < ApplicationPolicy
  def index? = @account_user.mes_staff?
  def show? = index?

  # 建单与单据维护：工程/PMC。
  def create? = schedulable?
  def update? = schedulable?
  def destroy? = schedulable?
  def confirm? = schedulable?
  def close? = schedulable?

  # 料的出入库：仓管。工程/PMC 也放行——小批量时常是同一个人从头跟到尾，
  # 卡死在这一步只会逼他们去借仓管账号。
  def issue? = stockable?
  def receipt? = stockable?
  def return_materials? = stockable?

  def generate_fee? = @account_user.crm_finance? || @account_user.administrator?

  private

  def schedulable? = @account_user.mes_can?(:bom)
  def stockable? = @account_user.mes_can?(:stock) || schedulable?
end

Mes::OutsourceOrderPolicy.prepend_mod_with('Mes::OutsourceOrderPolicy')
