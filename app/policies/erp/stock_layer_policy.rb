class Erp::StockLayerPolicy < ApplicationPolicy
  # 读：能进 ERP 的成员即可（存货成本是 ERP 内部数据，销售端进不来）。
  def index? = @account_user.can_access_erp?

  # 期初导入与期初建账同级（close 能力）——它同样是「账的地基」，不该让出纳改。
  def import? = @account_user.erp_can?(:close)
  def import_template? = import?
end
