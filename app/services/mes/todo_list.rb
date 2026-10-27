# 「这个人现在能办的事」——MES 待办的**唯一权威出口**。
#
# 为什么要有它：以前「谁该办什么」散在六处控制器私有方法里，App 只能把
# `notifications?unread=true` 和各个 inbox 拼起来猜，于是
#   · 周知类通知被当成待办（未读 ≠ 没办完）
#   · 同一笔审批在通知和 inbox 各出现一次，重复计数
#   · 阶段流转或权限变动后，旧通知看着还能办
#
# 三条硬规矩：
#   1. **不另写一套角色推导。** 这里的判定全是从控制器搬过来的原件，控制器反过来
#      调它（inbox / todo_count / acknowledge），所以不存在两套口径。
#   2. **计数与列表同一份查询。** counts 直接数 items，杜绝「角标 3、点进去 2」。
#   3. **看单据当下状态，不看通知的 read_at。** 「点开看过」不等于「办完了」。
class Mes::TodoList
  # 采购原料阶段的三态：待下单 / 等料中 / 催货。
  #
  # 别的阶段干完活订单就往下走了，待办自然消失；只有**采购原料**例外——下完采购单后
  # 订单要等料到齐（齐套闸）才进原料入库。原先不区分，采购把单都下完了，待办里还
  # 一直挂着「待处理 · 去下采购单」（生产上 10 条里 9 条是这种）。但一律藏掉也不对：
  # 单子还卡在采购阶段等货，只是没人看见了，那是更糟的积压。所以按「要不要人动手」分三档：
  #   TODO    没下采购单            → 催他下单，进角标
  #   WAITING 下了单、还没到交期     → 正常等货，列出来但不催、不进角标
  #   URGING  下了单、过了交期没到齐 → 该催供应商了，进角标（这才是真积压）
  # 交期取采购单的「交货时间」，没填回落「回复交期」；两个都没填就当还没到期。
  PURCHASE_STATES = { todo: 'TODO', waiting: 'WAITING', urging: 'URGING' }.freeze

  def initialize(account:, account_user:)
    @account = account
    @au = account_user
    @uid = account_user&.user_id
  end

  # 结构化条目。key 形如 mes:<subject_type>:<subject_id>:<action_type>，
  # 同一单据的不同动作 key 不同——不会被 App 误合并成一条。
  def items
    return [] if @au.blank?

    @items ||= production_approvals + stage_acks + bom_confirms + sales_return_confirms +
               shipment_approval_items + purchase_approvals + entry_posts
  end

  # 角标。与 items 同一份数据，不另跑一套查询。
  # 角标。与 items 同一份数据，不另跑一套查询。
  COUNT_KEYS = {
    approval: %w[production_approval], inbox: %w[stage_ack],
    shipment: %w[shipment_approval], purchase: %w[purchase_approval],
    confirm: %w[confirm_bom sales_return_confirm], entry: %w[entry_post]
  }.freeze

  def counts
    by = items.group_by { |i| i[:action_type] }
    COUNT_KEYS.transform_values { |kinds| kinds.sum { |k| by[k].to_a.size } }
              .merge(total: items.size)
  end

  # ── 控制器复用的原件（搬过来的，控制器反过来调这里）────────────────

  # 我负责的在产订单（= 我管的那个阶段上停着的单）。
  def inbox_orders
    @inbox_orders ||= begin
      open_orders = @account.mes_production_orders.published
                            .where(status: 'IN_PROGRESS').where.not(stage: 'SHIPPED')
                            .includes(:stage_events).order(created_at: :desc)
      open_orders.select { |po| stage_owner_of?(po) }
    end
  end

  def purchase_state_map(orders)
    ids = orders.select { |po| po.stage == 'PURCHASING' }.map(&:id)
    return {} if ids.empty?

    rows = @account.mes_purchase_orders
                   .where(production_order_id: ids).where.not(status: 'CANCELLED')
                   .pluck(:production_order_id, :status, :delivery_date, :expected_date)
    by_order = rows.group_by(&:first)
    ids.index_with { |id| state_for(by_order[id]) }
  end

  # 这一段该不该归我这个岗位。
  # BOM 板块负责人里有人没配 MES 岗位（老数据），对他们保持原样全给——
  # 按岗位硬筛会让这些人的待办凭空消失，那比多显示几条糟得多。
  def ack_role_match?(order)
    role = order.ack_role
    return true if role.blank?

    mine = @au.effective_mes_roles
    return true unless mine.intersect?(Mes::ProductionOrder::STAGE_ACK_ROLES.values)

    mine.include?(role)
  end

  # 待我审核的出库单。
  #
  # 原先这里是 `where(kind: 'STOCK').where(manager_id: current_user.id)`，两处都错：
  #   · manager_id 在 submit_for_approval! 里被置 nil（审核的财务是一组人，审的时候
  #     才定），所以非管理员永远匹配不上，角标恒为 0；
  #   · 只数现货（STOCK），可 ship! 要求两种 kind 都得财务审过。
  # 生产上唯一一张待审出库单是 PRODUCTION 类型、manager_id 为 nil，于是**所有人**
  # 的角标都显示 0——那张单因此挂了 30 小时没人知道（通知那条路同根，已另修）。
  # 现改用与挡写、与待审核通知收件人同一个口径：Mes::Shipment#approver_for?。
  def shipment_approvals
    @shipment_approvals ||= @account.mes_shipments.where(status: 'PENDING_APPROVAL')
                                    .includes(:crm_sales_order).select { |s| s.approver_for?(@au) }
  end

  private

  # ── 六条来源 ────────────────────────────────────────────────

  # 生产订单审批：停在我这一级的（部门主管 / 总经理）。
  def production_approvals
    base = @account.mes_production_orders
    base.awaiting_manager_for(@uid).or(base.awaiting_gm_for(@uid)).map do |po|
      item(po, 'production_order', 'production_approval',
           "待审批：#{po.order_no}",
           po.approval_status == 'SUBMITTED' ? '等你以部门主管身份审批' : '等你以总经理身份审批',
           po.approval_status, po.updated_at)
    end
  end

  # 阶段接单 / 采购催办：只算真要人动手的那两档（见 PURCHASE_STATES 注释）。
  def stage_acks
    states = purchase_state_map(inbox_orders)
    inbox_orders.filter_map do |po|
      next unless actionable_todo?(po, states[po.id])

      item(po, 'production_order', 'stage_ack',
           "#{po.stage == 'PURCHASING' ? '采购原料' : '待接单'}：#{po.order_no}",
           stage_ack_subtitle(po, states[po.id]), po.stage, po.stage_entered_at)
    end
  end

  def stage_ack_subtitle(order, state)
    return '还没下采购单' if state == PURCHASE_STATES[:todo]
    return '采购单过了交期还没到齐，该催供应商了' if state == PURCHASE_STATES[:urging]

    "这一段归你，还没接单#{order.ack_overdue? ? '（已超时）' : ''}"
  end

  # BOM 业务确认：工程排好用料，等业务点头才能下发采购。
  # 用 *_assigned_to? 而不是 can_confirm_bom?：后者含管理员/副管兜底，那是「能不能代办」，
  # 不是「派给了谁」。混用会让副管的待办里躺满全公司的用料确认（见 ProductionOrder 那两个方法）。
  def bom_confirms
    @account.mes_production_orders.where(stage: 'BOM_READY').where(bom_confirmed_at: nil)
            .where.not(bom_id: nil).select { |po| po.bom_confirm_assigned_to?(@au) }
            .map do |po|
      item(po, 'production_order', 'confirm_bom',
           "确认用料：#{po.order_no}", '工程已排好用料，等你确认后才能下发采购',
           po.stage, po.updated_at)
    end
  end

  # 业务退回确认：工程/PMC 把单退回来，等业务把细节补清楚。
  def sales_return_confirms
    @account.mes_production_orders.where.not(sales_return_at: nil)
            .where(sales_return_resolved_at: nil)
            .select { |po| po.sales_return_assigned_to?(@au) }
            .map do |po|
      item(po, 'production_order', 'sales_return_confirm',
           "退回待确认：#{po.order_no}",
           "#{po.sales_return_by&.name || '工程/PMC'}退回：#{po.sales_return_reason.to_s.truncate(40)}",
           po.stage, po.sales_return_at)
    end
  end

  # 待过账的出入库单（领料/入库/出库的草稿）。
  #
  # 补这一类是因为仓库岗在统一待办里原本**一条都没有**：六类来源全是订单流转和审批，
  # 仓管开了单没过账就只能自己记着。生产实查只有 1 张（挂了 3 天），量很小但正是
  # 该被看见的那种——单子躺在草稿里，库存账没动，后面所有人都在等它。
  #
  # 归制单人：过账这个动作就是他做。成品入库要车间和仓管双确认，但那道卡在
  # dual_confirm 上、不在「谁该点过账」上（见 Mes::DocDiagnosis#entry_post）。
  def entry_posts
    @account.mes_stock_entries.where(status: 'DRAFT', owner_id: @au.user_id).map do |entry|
      item(entry, 'stock_entry', 'entry_post',
           "待过账：#{entry.entry_no}", '单据还在草稿，过账后库存账才会动',
           entry.status, entry.created_at)
    end
  end

  # 出库审核（财务审「款收齐没有」；小额单仓库自己批）。
  def shipment_approval_items
    shipment_approvals.map do |s|
      item(s, 'shipment', 'shipment_approval',
           "待审核：#{s.shipment_no}",
           s.warehouse_self_approvable? ? '小额单，仓库可自行审核放行' : '等财务核对款项收齐没有',
           s.status, s.submitted_at)
    end
  end

  # 采购单审批：停在总经理这一级的。
  def purchase_approvals
    @account.mes_purchase_orders.awaiting_gm_for(@uid).map do |po|
      item(po, 'purchase_order', 'purchase_approval',
           "待审批采购单：#{po.po_no}", '等你审批后采购才能下单', po.approval_status, po.updated_at)
    end
  end

  # ── 条目构造 ────────────────────────────────────────────────

  # rubocop:disable Metrics/ParameterLists -- 条目构造器，参数摊开比塞进 hash 让人猜键名清楚
  def item(record, subject_type, action_type, title, subtitle, status, since)
    { key: "mes:#{subject_type}:#{record.id}:#{action_type}",
      subject_type: subject_type, subject_id: record.id,
      subject_no: record.try(:order_no) || record.try(:shipment_no) || record.try(:po_no) || record.try(:entry_no),
      action_type: action_type, title: title, subtitle: subtitle,
      status: status, actionable: true, since: since }
  end
  # rubocop:enable Metrics/ParameterLists

  # ── 搬过来的判定原件 ────────────────────────────────────────

  def actionable_todo?(order, state)
    return [PURCHASE_STATES[:todo], PURCHASE_STATES[:urging]].include?(state) if order.stage == 'PURCHASING'

    order.awaiting_ack?
  end

  # 我是这张单当前阶段的板块负责人吗（本产线优先，回落「全部产线」的通用负责人）。
  # 开头两段还要再过一道岗位：工程那段不进 PMC 的待办，PMC 那段也不进工程的。
  def stage_owner_of?(order)
    key = Mes::ProductionOrder::INBOX_BOARD_KEYS[order.stage]
    return false if key.blank?
    return false if order.ack_skipped?
    return false unless ack_role_match?(order)

    stage_owner_ids(key, order.product_line.to_s).include?(@uid)
  end

  def stage_owner_ids(key, line)
    @board_owners_by_key_line ||= @account.mes_board_owners.to_a
                                          .index_by { |o| [o.board_key, o.product_line.to_s] }
    (line.present? && @board_owners_by_key_line[[key, line]]&.manager_ids.presence) ||
      @board_owners_by_key_line[[key, '']]&.manager_ids || []
  end

  def state_for(purchase_rows)
    return PURCHASE_STATES[:todo] if purchase_rows.blank?

    PURCHASE_STATES[purchase_rows.any? { |r| overdue_purchase?(r) } ? :urging : :waiting]
  end

  # 还没收齐（非 RECEIVED）且交期已过。
  def overdue_purchase?(row)
    _id, status, delivery_date, expected_date = row
    return false if status == 'RECEIVED'

    due = delivery_date || expected_date&.to_date
    due.present? && due < Date.current
  end
end
