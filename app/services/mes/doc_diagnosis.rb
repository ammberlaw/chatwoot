# 「这张单为什么做不了这件事」——AI 助手调的统一诊断出口。
#
# 用户卡住时的真实形态不止「点了报错」，更多是「按钮根本不在」「提交完没动静」。
# 所以问的不是「解释这条报错」，而是**诊断这个动作**：做得了做不了、卡在哪、
# 下一步该谁动、那个人知不知道。报错的和没报错的用同一套判定，因为挡住他的本来
# 就是同一套判定。
#
# 三条硬规矩（2026-10-23/24 踩出来的）：
#   1. **一行裸 SQL 都不许写。** 那两天手写查询两次：一次漏 crm_finance（审核人 4 个
#      算成 2 个），一次漏 default_scope（待审 5 张算成 8 张）。绕过模型直接查表就会
#      漏掉模型里写着的规则，而诊断答错比不答更糟——它会理直气壮地把人支到错地方。
#   2. **只调已经抽出来的谓词。** 这里一条判定都不新写，全是调模型/policy/TodoList。
#   3. **只读。** 绝不改数据、绝不发通知。
# rubocop:disable Metrics/ClassLength -- 三类单据的判定有意收在一处；拆开要在调用方再分发一次
class Mes::DocDiagnosis
  class << self
    # 按单号找单，认不出来就说认不出来——绝不猜一张相近的（猜错会斩钉截铁地说错话）。
    def locate(account, doc_no)
      no = doc_no.to_s.strip
      return nil if no.blank?

      account.mes_shipments.find_by(shipment_no: no) ||
        account.mes_production_orders.find_by(order_no: no) ||
        account.mes_purchase_orders.find_by(po_no: no) ||
        account.mes_stock_entries.find_by(entry_no: no)
    end

    def for(record, account_user)
      case record
      when Mes::Shipment then Mes::ShipmentDiagnosis.new(shipment: record, account_user: account_user)
      when Mes::ProductionOrder then new(record, account_user, ORDER_ACTIONS)
      when Mes::PurchaseOrder then new(record, account_user, PURCHASE_ACTIONS)
      when Mes::StockEntry then new(record, account_user, ENTRY_ACTIONS)
      end
    end
  end

  # 每个动作一条：中文名 + 判定方法名。判定返回 blocker 数组（空数组＝做得了）。
  ORDER_ACTIONS = {
    'submit_approval' => ['提交审批', :order_submit],
    'approve' => ['审批', :order_approve],
    'acknowledge' => ['接单', :order_ack],
    'confirm_bom' => ['确认用料', :order_confirm_bom],
    'resolve_sales_return' => ['确认退回', :order_resolve_return],
    'return_to_sales' => ['退回业务', :order_return],
    'release_purchasing' => ['下发采购', :order_release]
  }.freeze

  PURCHASE_ACTIONS = { 'approve' => ['审批采购单', :po_approve] }.freeze
  ENTRY_ACTIONS = { 'post' => ['过账', :entry_post] }.freeze

  def initialize(record, account_user, actions)
    @r = record
    @au = account_user
    @actions = actions
    @account = record.account
  end

  # action 省略＝把这张单上**所有**动作过一遍，用户说不清想干什么时用。
  def call(action = nil)
    keys = action.present? ? [resolve_action(action)].compact : @actions.keys
    return { error: "这类单据上没有「#{action}」这个操作，可做的是：#{@actions.values.map(&:first).join('、')}" } if keys.empty?

    { doc_no: doc_no, doc_type: doc_type, status_label: status_label,
      actions: keys.map { |k| one(k) }, waiting_on: waiting_on }
  end

  # 调用方传的是人话还是内部 key 都认——用户说的永远是「接单」，不会是 acknowledge。
  # 先按中文名精确对，再按别名包含对；两头都不中就宁可答「没这个操作」，不猜。
  ACTION_ALIASES = {
    'submit_approval' => %w[提交 送审 报审], 'approve' => %w[审批 审核 批准 通过],
    'acknowledge' => %w[接单 领单 认领], 'confirm_bom' => %w[确认用料 用料 BOM 物料确认],
    'resolve_sales_return' => %w[确认退回 处理退回], 'return_to_sales' => %w[退回业务 退单 打回],
    'release_purchasing' => %w[下发采购 下采购 请购], 'post' => %w[过账 入账 记账]
  }.freeze

  private

  def resolve_action(action)
    text = action.to_s.strip
    return text if @actions.key?(text)

    by_label = @actions.find { |_k, (label, _m)| label == text }&.first
    return by_label if by_label

    @actions.keys.find { |k| Array(ACTION_ALIASES[k]).any? { |w| text.include?(w) } }
  end

  def one(key)
    label, method = @actions[key]
    blockers = send(method)
    { action: key, action_label: label, blocked: blockers.any?, blockers: blockers }
  end

  def block(text, fix: nil) = { text: text, fix: fix }.compact

  def doc_no = @r.try(:order_no) || @r.try(:po_no) || @r.try(:entry_no)

  def doc_type
    { 'Mes::ProductionOrder' => '销售订单', 'Mes::PurchaseOrder' => '采购单',
      'Mes::StockEntry' => '出入库单' }[@r.class.name]
  end

  def admin_like? = @au.administrator? || @au.crm_deputy_admin?

  # ── 下一步等谁：直接问统一可办出口，不另算一遍 ────────────────
  def waiting_on
    items = Mes::TodoList.new(account: @account, account_user: @au).items
    mine = items.select { |i| i[:subject_no] == doc_no }
    # 这张单在**别人**手上时，TodoList 查的是我自己的，查不到——所以再按单据状态答一次。
    return { label: '在你手上', names: [], mine: mine.pluck(:action_type) } if mine.any?

    owner_hint
  end

  def owner_hint
    case @r
    when Mes::ProductionOrder then order_owner_hint
    when Mes::PurchaseOrder then po_owner_hint
    end
  end

  # 采购单只有一道审批。审完了这张单就不在「等人」了——
  # 不加这一道，已审批的单会被答成「等总经理审批」，用户照着去催一个根本不用动的人。
  def po_owner_hint
    return { label: '等总经理审批', names: User.where(id: @r.gm_id).pluck(:name) } if @r.approval_status == 'SUBMITTED'
    return { label: '还没提交审批，在制单人手上', names: User.where(id: @r.try(:created_by_id)).pluck(:name) } if
      @r.approval_status == 'DRAFT'

    { label: "审批已完成（#{cn(PO_APPROVAL_CN, @r.approval_status)}），不在等人审", names: [] }
  end

  def order_owner_hint
    if @r.approval_status == 'SUBMITTED'
      { label: '等部门主管审批', names: User.where(id: @r.manager_id).pluck(:name) }
    elsif @r.approval_status == 'MANAGER_APPROVED'
      { label: '等总经理审批', names: User.where(id: @r.gm_id).pluck(:name) }
    elsif @r.awaiting_sales_confirm?
      { label: '等业务确认退回', names: User.where(id: @r.owner_id).pluck(:name) }
    elsif @r.awaiting_bom_confirm?
      { label: '等业务确认用料', names: User.where(id: @r.owner_id).pluck(:name) }
    else
      { label: "等#{Mes::ProductionOrder::STAGE_LABELS[@r.stage] || @r.stage}这一段的负责人",
        names: User.where(id: @r.current_stage_owner_ids).pluck(:name) }
    end
  end

  # 文案照界面上那套中文翻，别把 SUBMITTED / PARTIAL_RECEIVED 这种码值答给用户——
  # 他屏幕上从来没见过这些词，照着去找对不上。
  ORDER_APPROVAL_CN = { 'DRAFT' => '草稿', 'SUBMITTED' => '待部门主管审批',
                        'MANAGER_APPROVED' => '待总经理审批', 'APPROVED' => '已通过·生效',
                        'REJECTED' => '已驳回' }.freeze
  PO_STATUS_CN = { 'DRAFT' => '草稿', 'SUBMITTED' => '已下单', 'PARTIAL_RECEIVED' => '部分到货',
                   'RECEIVED' => '已到货', 'CANCELLED' => '已关闭' }.freeze
  PO_APPROVAL_CN = { 'DRAFT' => '草稿', 'PENDING_GM' => '待审批', 'SUBMITTED' => '待审批',
                     'APPROVED' => '已通过', 'REJECTED' => '已驳回' }.freeze
  ENTRY_STATUS_CN = { 'DRAFT' => '草稿', 'POSTED' => '已过账', 'CANCELLED' => '已作废' }.freeze

  def status_label
    case @r
    when Mes::ProductionOrder
      "#{stage_cn} / 审批：#{cn(ORDER_APPROVAL_CN, @r.approval_status)}"
    when Mes::PurchaseOrder
      "#{cn(PO_STATUS_CN, @r.status)} / 审批：#{cn(PO_APPROVAL_CN, @r.approval_status)}"
    when Mes::StockEntry then cn(ENTRY_STATUS_CN, @r.status)
    end
  end

  # 翻不出来就把码值原样带上——悄悄吞掉会让新加的状态变成一句空话。
  def cn(map, code) = map[code.to_s] || code.to_s

  # ── 销售订单（MES 里 mes_production_orders 一律叫「销售订单」）──────
  def order_submit
    out = []
    out << block(not_draft_text('提交审批')) if %w[DRAFT REJECTED].exclude?(@r.approval_status)
    unless @r.owner_id == @au.user_id || admin_like?
      out << block('只有创建人能提交审批，这张单是别人建的。',
                   fix: "找 #{@r.owner&.name || '建单人'} 提交，或请管理员代提。")
    end
    out
  end

  def not_draft_text(what)
    "这张单现在是「#{cn(ORDER_APPROVAL_CN, @r.approval_status)}」，只有草稿和被驳回的单能#{what}。"
  end

  def order_approve
    out = []
    out << block("这张单现在是「#{cn(ORDER_APPROVAL_CN, @r.approval_status)}」，不在待审批环节。") if
      %w[SUBMITTED MANAGER_APPROVED].exclude?(@r.approval_status)
    unless approver_now?
      who = @r.approval_status == 'SUBMITTED' ? @r.manager : @r.gm
      out << block('你不是这一环节的审批人。', fix: who ? "该审的是 #{who.name}。" : nil)
    end
    out
  end

  # 与控制器 can_approve? 同口径：本环节指定审批人本人；上一级是我批的就不给我批下一级。
  def approver_now?
    case @r.approval_status
    when 'SUBMITTED' then @r.manager_id == @au.user_id || (admin_like? && @r.owner_id != @au.user_id)
    when 'MANAGER_APPROVED' then @r.gm_id == @au.user_id || (admin_like? && @r.manager_acted_by_id != @au.user_id)
    else false
    end
  end

  def order_ack
    out = []
    out << block('这张单当前阶段不需要接单，或者已经接过了。') unless @r.awaiting_ack?
    out << ack_owner_block unless admin_like? || @r.current_stage_owner_ids.include?(@au.user_id)
    out << block("这一段归#{@r.ack_role_label}接单，你的岗位不是这个。") if out.empty? && ack_role_mismatch?
    out
  end

  def ack_owner_block
    names = User.where(id: @r.current_stage_owner_ids).pluck(:name)
    block('你不是这一段的负责人。',
          fix: names.any? ? "该接单的是 #{names.join('、')}。" : '这一段还没配负责人，找管理员在「板块负责人」里配上。')
  end

  def ack_role_mismatch?
    !admin_like? && @r.ack_role.present? && @au.effective_mes_roles.exclude?(@r.ack_role)
  end

  def order_confirm_bom
    return [] if @r.can_confirm_bom?(@au)

    out = []
    out << block('这张单现在不在「等业务确认用料」这一步。') unless @r.awaiting_bom_confirm?
    out << owner_only_block('确认用料') unless @r.owner_id == @au.user_id || admin_like?
    out
  end

  def owner_only_block(what)
    block("只有这张单的归属业务员能#{what}。", fix: "该确认的是 #{@r.owner&.name || '归属业务员'}。")
  end

  def order_resolve_return
    return [] if @r.can_resolve_sales_return?(@au)

    out = []
    out << block('这张单没有待确认的退回。') unless @r.awaiting_sales_confirm?
    out << owner_only_block('确认退回') unless @r.owner_id == @au.user_id || admin_like?
    out
  end

  def order_return
    return [] if @r.can_return_to_sales?(@au.user)

    out = []
    out << block(stage_not_returnable_text) unless Mes::ProductionOrder::RETURNABLE_STAGES.include?(@r.stage)
    out << block('这张单已经退回过了，还在等业务确认。') if @r.awaiting_sales_confirm?
    out << block('只有本阶段负责人能退回。') unless @r.current_stage_owner_ids.include?(@au.user_id)
    out
  end

  def stage_not_returnable_text
    ok = Mes::ProductionOrder::RETURNABLE_STAGES.map { |x| Mes::ProductionOrder::STAGE_LABELS[x] || x }.join('、')
    "只有「#{ok}」阶段能退回业务，这张单在「#{stage_cn}」。"
  end

  def stage_cn = Mes::ProductionOrder::STAGE_LABELS[@r.stage] || @r.stage

  def order_release
    out = []
    if @r.awaiting_bom_confirm?
      out << block('这张单还在等业务确认用料，确认完才能下发采购。',
                   fix: "等 #{@r.owner&.name || '业务'} 点「确认用料无误」。")
    end
    if @r.bom_id.blank?
      out << block('这张单还没挂生产任务单（BOM），没有用料清单就没法下发采购。',
                   fix: '先在订单上「关联已有生产任务单」或新建一张。')
    end
    out
  end

  # ── 采购单 ────────────────────────────────────────────────
  def po_approve
    out = []
    out << block("这张采购单现在是「#{cn(PO_APPROVAL_CN, @r.approval_status)}」，不在待审批环节。") unless
      @r.approval_status == 'SUBMITTED'
    unless @r.gm_id == @au.user_id || admin_like?
      out << block('你不是这张采购单的审批人。',
                   fix: @r.gm ? "该审的是 #{@r.gm.name}。" : nil)
    end
    out
  end

  # ── 出入库单 ──────────────────────────────────────────────
  def entry_post
    # 已过账/已作废的单不查缺料：库存正是这张单自己扣掉的，查出来必然是「只有 0」，
    # 报给用户纯属误导——这种单唯一的阻碍就是状态本身。
    return [block("这张单现在是「#{cn(ENTRY_STATUS_CN, @r.status)}」，只有草稿能过账。")] unless @r.status == 'DRAFT'

    out = []
    out << block(@r.approval_blocker) if @r.respond_to?(:approval_blocker) && @r.approval_blocker.present?
    out << dual_confirm_block if @r.dual_confirm_required? && !@r.dual_confirmed?
    out + stock_blocks
  end

  def dual_confirm_block
    block('成品入库要车间负责人和仓管都确认过才能过账。', fix: '缺哪一方的确认，在单据上能看到谁还没签。')
  end

  def stock_blocks = @r.stock_shortages.map { |row| shortage_block(row) }

  # 原料不够时顺带看一眼成品账，反之亦然——同一个编码两本账是这边最常撞的坎
  # （见 MES_SYSTEM §4.8bis）。
  def shortage_block(row)
    base = "#{row[:item_name]}：这个仓的#{book_cn(row[:item_type])}账只有 #{fnum(row[:on_hand])}，" \
           "这张单要 #{fnum(row[:need])}。"
    rows = other_book_rows(row)
    return block(base) if rows.blank?

    where = rows.map { |b| "#{b.warehouse&.name || '仓库'} #{fnum(b.qty)}" }.join('、')
    block(base, fix: "同一个编码的#{book_cn(other_book(row))}账上有货（#{where}），" \
                     '要先让仓管在「原料成品转换」里转过来才能用。')
  end

  def other_book(row) = row[:item_type] == 'PRODUCT' ? 'MATERIAL' : 'PRODUCT'
  def book_cn(kind) = kind == 'PRODUCT' ? '成品' : '原料'

  def other_book_rows(row)
    return [] if row[:crm_product_id].blank?

    @account.mes_stock_balances.where(item_type: other_book(row), crm_product_id: row[:crm_product_id])
            .where('qty > 0').to_a
  end

  def fnum(value) = format('%g', value.to_f)
end
# rubocop:enable Metrics/ClassLength
