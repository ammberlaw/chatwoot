# 「今天要做的」——一个人今天手上所有待办的统一出口。
#
# 为什么要合并：日程表原先只有销售线有内容（133/181 条是客户来信自动塞的
# 「回复客户来信」），41 个成员里只有 12 个人日程里有东西。仓库、生产、财务打开
# 日程是一片空白，再怎么优化界面他们也不会用。
# 而他们手上真有事：该接的单、该过账的出入库、该审的出库单——这些都在
# Mes::TodoList 里现成的，只是没人把它们摆到一处。
#
# 🔴 合并在**读的时候**做，不往日程表里写派生记录。写进去就要管同步：
# 单子审完了日程还挂着、删了单日程变孤儿、同一件事两处状态不一致。
# 这些坑今天已经在别处踩过一轮（角标与面板对不上、回信不销提醒）。
#
# 两类条目的办结方式不同，前端要分开渲染：
#   schedule —— 日程，能直接打勾（toggle_done）
#   todo     —— 业务待办，勾不掉，得去对应单据上做那个动作，所以给跳转
class Crm::MyDay
  def initialize(account:, account_user:)
    @account = account
    @au = account_user
  end

  def items
    return [] if @au.blank?

    all = schedule_items + mes_items + sales_order_items + kpi_items
    # 勾掉的沉到底，但**留在列表里划掉**——当场消失会让人怀疑「我刚才点的那条是不是点错了」，
    # 而且一天下来看不到自己做完了什么。
    all.sort_by { |i| [i[:done] ? 1 : 0, i[:sort_at]] }
  end

  private

  def user_id = @au.user_id

  # ── 今天的日程（含系统塞的回信提醒）──────────────────────────
  def schedule_items
    today = Time.zone.today
    @account.crm_schedule_events.visible_to(user_id).flat_map do |event|
      done = event.completed_dates.to_a.map(&:to_s)
      event.occurrences_in(today.beginning_of_day, today.end_of_day)
           .map { |occ| schedule_row(event, occ, done.include?(occ[:starts_at].to_date.to_s)) }
    end
  end

  SCHEDULE_LABEL = {
    'reply_reminder' => '回信', 'opp_follow_up' => '商机', 'follow_up' => '跟进'
  }.freeze

  def schedule_row(event, occ, done)
    { type: 'schedule', id: event.id, occurrence_date: occ[:starts_at].to_date.to_s,
      title: event.title, done: done,
      label: event.all_day? ? (SCHEDULE_LABEL[event.kind] || '全天') : occ[:starts_at].in_time_zone.strftime('%H:%M'),
      # 全天的排在带时间的前面：全天是「今天之内做完」，有点的是「到点要在」。
      sort_at: event.all_day? ? Time.zone.today.beginning_of_day : occ[:starts_at] }
  end

  # ── MES：接单 / 审批 / 确认用料 / 确认退回 / 出库审核 / 采购审批 ──
  TARGET_ROUTE = {
    'production_approval' => 'mes_production_orders_index', 'stage_ack' => 'mes_production_orders_index',
    'confirm_bom' => 'mes_production_orders_index', 'sales_return_confirm' => 'mes_production_orders_index',
    'shipment_approval' => 'mes_shipments_index', 'purchase_approval' => 'mes_purchase_orders_index',
    'entry_post' => 'mes_stock_entries_index'
  }.freeze
  ACTION_LABEL = {
    'production_approval' => '待审批', 'stage_ack' => '待接单', 'confirm_bom' => '确认用料',
    'sales_return_confirm' => '确认退回', 'shipment_approval' => '出库审核', 'purchase_approval' => '采购审批',
    'entry_post' => '待过账'
  }.freeze

  def mes_items
    Mes::TodoList.new(account: @account, account_user: @au).items.map do |todo|
      { type: 'todo', id: todo[:key], title: todo[:title], done: false,
        label: ACTION_LABEL[todo[:action_type]] || 'MES',
        route: TARGET_ROUTE[todo[:action_type]], query: { q: todo[:subject_no] }.compact,
        # 挂得越久排越前——真正被忘掉的就是这些。
        sort_at: todo[:since] || Time.zone.now }
    end
  end

  # ── 销售订单待我审 ────────────────────────────────────────
  def sales_order_items
    Crm::SalesOrderApprover.pending_scope(@account, @au).limit(20).map do |order|
      { type: 'todo', id: "so:#{order.id}", title: "待审核销售订单：#{order.order_no}", done: false,
        label: '订单审核', route: 'crm_sales_orders_index', query: { approval: 'PENDING' },
        sort_at: order.updated_at }
    end
  end

  # ── 绩效考核待我动 ────────────────────────────────────────
  def kpi_items
    Crm::KpiReminderJob.actionable_for(@account, @au).limit(20).map do |sheet|
      { type: 'todo', id: "kpi:#{sheet.id}", title: "绩效考核：#{sheet.scheme_name}", done: false,
        label: Crm::KpiReminderJob::STEPS[sheet.status] || '待处理',
        route: 'crm_kpi_sheet_detail', query: { id: sheet.id.to_s },
        sort_at: sheet.updated_at }
    end
  end
end
