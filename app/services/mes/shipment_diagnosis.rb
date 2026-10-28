# 「我为什么干不了这件事」——出库单的自助诊断。
#
# 用户卡住时的真实形态不止「点了报错」，更多是「按钮根本不在」「提交完没动静」。
# 所以入口不是「解释这条报错」，是「诊断这个动作」：问的是做得了做不了、卡在哪、
# 下一步该谁动、那个人知不知道。报错的和没报错的用同一套判定，因为挡住他的本来
# 就是同一套判定。
#
# 三条硬规矩（都是 2026-10-23 踩出来的）：
#
# 1. **一行裸 SQL 都不许写。** 当天手写查询两次：一次漏了 crm_finance（审核人 4 个
#    算成 2 个），一次漏了 default_scope（待审 5 张算成 8 张，3 张在回收站）。绕过
#    模型直接查表就会漏掉模型里写着的规则，而诊断答错比不答更糟——它会理直气壮地
#    把人支到错的地方去。
# 2. **只调已经抽出来的谓词，没抽的先抽。** stock_shortages / reservation_shortages
#    就是为此从 ensure_*! 里抽出来的，拦截与诊断共用同一份结果。
# 3. **只读。** 诊断绝不改数据、绝不发通知。补发做成用户点的按钮（见 notify_hint），
#    是他的动作，不是诊断的副作用。
class Mes::ShipmentDiagnosis
  ACTIONS = {
    'submit' => '提交审核',
    'approve' => '审核',
    'ship' => '出库'
  }.freeze

  # 某类通知是从哪天起才真的发得出去。没有这条基线，诊断会对每一张老单子喊
  # 「系统没通知他们」——而真相往往只是那会儿还没这个功能。一个天天报假警的
  # 东西，第三天就没人看了。
  #
  # shipment_approval_pending：代码一直在，但收件人取的是提交时刚被置空的
  # manager_id，八张单提交审核、一条通知没发出去（commit 40bf3b9ed 修）。
  NOTIFY_LIVE_SINCE = {
    'shipment_approval_pending' => Time.zone.parse('2026-10-23 15:27:00'),
    'shipment_approved' => Time.zone.parse('2026-01-01 00:00:00')
  }.freeze

  def initialize(shipment:, account_user:)
    @s = shipment
    @au = account_user
    @account = shipment.account
  end

  # action 省略＝把这张单上所有动作过一遍。用户说「这单出不了货」时往往说不清
  # 卡的是提交、审核还是出库本身，一次全报出来比追问一轮快。
  def call(action = nil)
    return all_actions if action.blank?

    key = resolve_action(action)
    return { error: "出库单上没有「#{action}」这个操作，可做的是：#{ACTIONS.values.join('、')}" } if key.nil?

    one(key, ACTIONS[key]).merge(
      doc_type: '出库单', doc_no: @s.shipment_no,
      status_label: status_label, waiting_on: waiting_on, notice: notice
    )
  end

  def all_actions
    { doc_type: '出库单', doc_no: @s.shipment_no, status_label: status_label,
      waiting_on: waiting_on, notice: notice,
      actions: ACTIONS.map { |key, label| one(key, label) } }
  end

  # 调用方（AI 工具、前端）传的是人话还是内部 key 都认。只收内部 key 的话，
  # 用户一说「提交」就诊断不出来，而他永远不会说 submit。
  ACTION_ALIASES = {
    'submit' => %w[提交 提交审核 提交审批 送审 报审],
    'approve' => %w[审核 审批 批准 通过],
    'ship' => %w[出库 出货 发货 发运]
  }.freeze

  def resolve_action(action)
    text = action.to_s.strip
    return nil if text.blank?
    return text if ACTIONS.key?(text)

    ACTION_ALIASES.find { |_key, words| words.any? { |w| text.include?(w) } }&.first
  end

  def one(key, label)
    blockers = send("#{key}_blockers")
    { action: key, action_label: label, blocked: blockers.any?, blockers: blockers }
  end

  # 这张单现在能做哪些动作——给前端摆「我干不了什么」的清单用。
  def self.actions_for(shipment)
    ACTIONS.map { |key, label| { action: key, label: label, relevant: relevant?(shipment, key) } }
  end

  def self.relevant?(shipment, action)
    case action
    when 'submit' then %w[DRAFT REJECTED PENDING_APPROVAL].include?(shipment.status)
    when 'approve' then %w[PENDING_APPROVAL APPROVED REJECTED].include?(shipment.status)
    when 'ship' then %w[APPROVED SHIPPED PENDING_APPROVAL].include?(shipment.status)
    else false
    end
  end

  private

  STATUS_LABELS = {
    'DRAFT' => '草稿', 'PENDING_APPROVAL' => '待审核', 'APPROVED' => '待出库',
    'REJECTED' => '被驳回', 'SHIPPED' => '已出库', 'CANCELLED' => '已作废'
  }.freeze

  def status_label = STATUS_LABELS[@s.status] || @s.status

  # 走真的 policy，不另写一份权限判断——「谁能干什么」有两处实现就一定会漂移，
  # 今天那个「通知零人」的 bug 根因就是这个（approver? 与通知收件人两套口径）。
  def policy
    @policy ||= Mes::ShipmentPolicy.new(
      { user: @au.user, account: @account, account_user: @au }, @s
    )
  end

  def block(text, fix: nil) = { text: text, fix: fix }.compact

  # ── 提交审核 ────────────────────────────────────────────────
  def submit_blockers
    out = []
    out << block("这张单现在是「#{status_label}」，只有草稿和被驳回的单能提交审核。") unless
      %w[DRAFT REJECTED].include?(@s.status)
    unless submit_permitted?
      out << block('只有开单人本人能提交审核，这张单是别人开的。',
                   fix: "找 #{@s.owner&.name || '开单人'} 提交，或请管理员代提。")
    end
    return out unless @s.stock?

    @s.reservation_shortages.each do |sh|
      out << block("#{sh[:product_name]}：可用现货只有 #{fnum(sh[:available])}，这张单要 #{fnum(sh[:need])}。" \
                   '（可用＝仓库实有 − 其他待出库单已经占掉的）')
    end
    out
  end

  def submit_permitted?
    policy.submit? && (@s.owner_id == @au.user_id || admin_like?)
  end

  # ── 审核 ────────────────────────────────────────────────────
  def approve_blockers
    out = []
    out << block("这张单现在是「#{status_label}」，只有待审核的单能审。") unless @s.status == 'PENDING_APPROVAL'
    unless @s.approver_for?(@au)
      who = User.where(id: @s.approval_notify_ids).pluck(:name)
      out << block('你不是这张单的审核人。', fix: who.any? ? "该审的是 #{who.join('、')}。" : nil)
    end
    paid = @s.fully_paid?
    out << block('这张单的款还没收齐。放行可以，但必须写明理由——不写系统不放。') if paid == false
    out
  end

  # ── 出库 ────────────────────────────────────────────────────
  def ship_blockers
    out = []
    out << block("这张单现在是「#{status_label}」，要财务审核通过（变成「待出库」）之后仓库才能出。") unless
      @s.status == 'APPROVED'
    out << block('出库是仓管的动作，你没有仓库权限。', fix: '找仓管出货。') unless policy.ship?
    @s.stock_shortages.each { |sh| out << shortage_block(sh) }
    out
  end

  # 2026-10-28 起出库同时认成品账和原料账（辅料配件本来就常态直接出，见 Mes::Shipment::BOOKS），
  # 所以 stock_shortages 给的 on_hand 已经是**两本合计**——这里不能再说「成品账只有 X」，
  # 那会让人以为去转一下账就能出，实际是这个仓真的不够。
  # 不够时改成顺带报别的仓有没有货：同一个编码多半是放错仓，调拨过来就能出。
  def shortage_block(shortage)
    base = "#{shortage[:product_name]}：这个仓（成品账+原料账）合计只有 #{fnum(shortage[:on_hand])}，" \
           "这张单要 #{fnum(shortage[:need])}。"
    others = @account.mes_stock_balances
                     .where(crm_product_id: shortage[:item].crm_product_id)
                     .where.not(warehouse_id: @s.warehouse_id)
                     .where('qty > 0')
    return block(base) if others.empty?

    where = others.map { |b| "#{b.warehouse&.name || '仓库'} #{fnum(b.qty)}" }.join('、')
    block(base, fix: "别的仓有货（#{where}），让仓管调拨过来，或者把这张单的出库仓改成那个仓。")
  end

  # ── 下一步等谁 ──────────────────────────────────────────────
  def waiting_on
    case @s.status
    when 'PENDING_APPROVAL' then actor('等人审核', @s.approval_notify_ids, 'shipment_approval_pending')
    when 'APPROVED' then actor('等仓库出货', warehouse_ids, 'shipment_approved')
    when 'REJECTED' then actor('等开单人改完重提', [@s.owner_id].compact, nil)
    end
  end

  def actor(label, ids, notify_kind)
    ids = ids.compact.uniq
    { label: label, names: User.where(id: ids).pluck(:name), user_ids: ids,
      since: @s.submitted_at, notified: notify_kind && notified_state(notify_kind) }
  end

  def warehouse_ids
    @account.mes_board_owners.find_by(board_key: Mes::Shipment::SHIPMENTS_BOARD_KEY)&.manager_ids || []
  end

  # 该收到通知的人到底收到没有。查不到且**那会儿这类通知已经能发了**才算系统的问题；
  # 单子比功能老就只是老，不是 bug。
  def notified_state(kind)
    count = @account.mes_notifications.where(kind: kind).where('title ILIKE ?', "%#{@s.shipment_no}%").count
    live_since = NOTIFY_LIVE_SINCE[kind]
    stamp = @s.submitted_at || @s.created_at
    supported = live_since.present? && stamp.present? && stamp >= live_since
    { count: count, supported: supported }
  end

  # 用户看到的那句话 + 要不要给他一个「知会」按钮（按钮归他点，诊断不发）。
  def notice
    w = waiting_on
    return nil if w.nil? || w[:notified].nil?
    return no_owner_notice if w[:names].empty?

    n = w[:notified]
    return nil if n[:count].positive?

    who = w[:names].join('、')
    if n[:supported]
      { level: 'warn', text: "系统查下来没给#{who}发过待办通知，他们可能不知道这张单在等他们。", can_notify: true }
    else
      { level: 'info', text: "这张单提交的时候系统还没有这类待办通知（功能比单子新），所以#{who}没收到过提醒。",
        can_notify: true }
    end
  end

  # 一个人都解析不出来＝这个环节根本没配负责人。这不是「没通知到」，是没人可通知，
  # 单子会一直挂着。这种配置缺口本身就该报出来，而不是拼一句没有主语的话。
  def no_owner_notice
    { level: 'warn', text: '但系统里没查到该负责这一步的人，这张单会一直挂着。',
      fix: '找管理员在 MES 的「板块负责人」里把这个环节配上。', can_notify: false }
  end

  def admin_like? = @au.administrator? || @au.crm_deputy_admin?
  def fnum(value) = format('%g', value.to_f)
end
