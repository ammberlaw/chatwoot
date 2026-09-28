# MES 所有控制器的基类。S0：任何本账号成员均可访问（生产/仓管/采购未必有 crm_role）；
# 角色收敛留到 S8。数据均以 Current.account 多租户隔离。
class Api::V1::Accounts::Mes::BaseController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 15

  private

  def page_param
    params[:page] || 1
  end

  # 单据「谁制单谁改」：非制单人不得修改，系统管理员可代改。
  # 同岗位之间原来是互相能改的（有 :order/:bom/:purchase 能力即可），结果业务做的单
  # 生产能随手改、反过来也一样，出了问题查不到人。制单人为空的老单不拦（没法判定）。
  def ensure_owner_or_admin!(record, label)
    return if Current.account_user&.administrator?
    return if record.owner_id.blank? || record.owner_id == current_user.id

    render json: { error: "#{label}只有制单人本人能修改，需要改请找管理员" }, status: :forbidden
  end

  # 当前切换的产品线（DISPLAY/TABLET），前端 axios 拦截自动注入；空=全部。
  def current_product_line
    params[:product_line].presence
  end

  # 按当前产品线收敛列表（供应商/仓库为共享物理资源，不参与分流，故不调用）。
  def scoped_by_product_line(scope)
    current_product_line ? scope.where(product_line: current_product_line) : scope
  end

  # 出库单专用：现货出库(STOCK)是跨产品线的共享库存，不按产品线分流——否则仓管切了产品线
  # 就找不到现货出库单去处理（点「待出库」通知落到空列表）。生产出库随其订单产品线正常分流。
  def scope_by_product_line_or_stock(scope)
    return scope unless current_product_line

    scope.where('kind = :stock OR product_line = :pl', stock: 'STOCK', pl: current_product_line)
  end

  # 业务可见范围：只有「纯业务（销售端）」按 Crm::AccessScope 收敛（业务员仅本人、主管本团队、
  # 管理员/副管理员全部）；其余人——非 CRM 成员、或持有任一 MES 流程角色（PMC/工程/采购/仓库/生产）
  # 的流程负责人——一律看全部订单：生产订单之后的整个流程都要能接手，看不到订单就没法干活。
  # 返回 :all 或可见 owner_id 数组。
  def mes_visible_owner_ids
    au = Current.account_user
    return :all if au.nil? || !au.can_access_crm? || au.effective_mes_roles.any?

    Crm::AccessScope.new(Current.account, au).visible_owner_ids
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

  # BOM 可见性跟着它挂的生产订单走：看得到订单（归属可见 或 备货单）就看得到其 BOM，
  # 外加自己起草的草稿。工程做 BOM 无需再单独关联业务员——BOM 天然经订单与业务员产生关系。
  def scoped_by_bom_visibility(scope)
    ids = mes_visible_owner_ids
    return scope if ids == :all

    order_bom_ids = Current.account.mes_production_orders
                           .where('owner_id IN (:ids) OR order_kind = :stock', ids: ids, stock: 'STOCK')
                           .where.not(bom_id: nil).select(:bom_id)
    scope.where('id IN (:bids) OR owner_id IN (:ids)', bids: order_bom_ids, ids: ids)
  end
end
