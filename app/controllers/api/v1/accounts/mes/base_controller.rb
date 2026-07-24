# MES 所有控制器的基类。S0：任何本账号成员均可访问（生产/仓管/采购未必有 crm_role）；
# 角色收敛留到 S8。数据均以 Current.account 多租户隔离。
class Api::V1::Accounts::Mes::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  private

  def page_param
    params[:page] || 1
  end

  # 当前切换的产品线（DISPLAY/TABLET），前端 axios 拦截自动注入；空=全部。
  def current_product_line
    params[:product_line].presence
  end

  # 按当前产品线收敛列表（供应商/仓库为共享物理资源，不参与分流，故不调用）。
  def scoped_by_product_line(scope)
    current_product_line ? scope.where(product_line: current_product_line) : scope
  end

  # 业务可见范围：CRM 业务角色按 Crm::AccessScope 收敛（业务员仅本人、主管本团队、
  # 管理员/副管理员全部）；非 CRM 成员（车间/仓管/采购等 MES 操作岗）不受限、看全部，
  # 否则他们看不到订单就没法干活。返回 :all 或可见 owner_id 数组。
  def mes_visible_owner_ids
    return :all unless Current.account_user&.can_access_crm?

    Crm::AccessScope.new(Current.account, Current.account_user).visible_owner_ids
  end

  # 生产订单按可见范围过滤（owner_id = 归属业务员）。
  # 备货订单（order_kind=STOCK，外贸共享库存）对全业务可见，不受 owner 收敛。
  def scoped_by_owner(scope)
    ids = mes_visible_owner_ids
    return scope if ids == :all

    scope.where('owner_id IN (:ids) OR order_kind = :stock', ids: ids, stock: 'STOCK')
  end

  # 下游单据按其关联生产订单的归属业务员过滤（业务员只看自己订单的单据）。
  # 备货订单的下游单据同样全业务可见。
  def scoped_by_order_owner(scope)
    ids = mes_visible_owner_ids
    return scope if ids == :all

    visible = Current.account.mes_production_orders
                     .where('owner_id IN (:ids) OR order_kind = :stock', ids: ids, stock: 'STOCK').select(:id)
    scope.where(production_order_id: visible)
  end

  # BOM 按订单归属业务员（sales_owner）过滤（制单人多为 PMC，故以归属业务员为准）。
  # 挂在备货订单上的 BOM 同样全业务可见。
  def scoped_by_sales_owner(scope)
    ids = mes_visible_owner_ids
    return scope if ids == :all

    stock_bom_ids = Current.account.mes_production_orders.stock.where.not(bom_id: nil).select(:bom_id)
    scope.where('sales_owner_id IN (:ids) OR id IN (:bids)', ids: ids, bids: stock_bom_ids)
  end
end
