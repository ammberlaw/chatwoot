# == Schema Information
#
# Table name: mes_shipments
#
#  id                  :bigint           not null, primary key
#  approve_note        :text
#  approved_at         :datetime
#  kind                :string           default("PRODUCTION"), not null
#  notified_at         :datetime
#  print_count         :integer          default(0), not null
#  product_line        :string
#  reject_reason       :text
#  remark              :text
#  shipment_no         :string           not null
#  shipped_at          :datetime
#  status              :string           default("DRAFT"), not null
#  submitted_at        :datetime
#  void_reason         :string
#  voided_at           :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_customer_id     :bigint
#  crm_sales_order_id  :bigint
#  manager_id          :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#  voided_by_id        :bigint
#  warehouse_id        :bigint
#
# Indexes
#
#  index_mes_shipments_on_account_and_product_line    (account_id,product_line)
#  index_mes_shipments_on_account_id                  (account_id)
#  index_mes_shipments_on_account_id_and_shipment_no  (account_id,shipment_no) UNIQUE
#  index_mes_shipments_on_crm_customer_id             (crm_customer_id)
#  index_mes_shipments_on_crm_sales_order_id          (crm_sales_order_id)
#  index_mes_shipments_on_manager_id                  (manager_id)
#  index_mes_shipments_on_owner_id                    (owner_id)
#  index_mes_shipments_on_production_order_id         (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_sales_order_id => crm_sales_orders.id) ON DELETE => nullify
#  fk_rails_...  (manager_id => users.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::Shipment < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  # PRODUCTION 出库：DRAFT → SHIPPED（生产流转，原样）。
  # STOCK 现货出库：PENDING_APPROVAL →(主管审核)→ APPROVED →(仓库)→ SHIPPED；驳回 REJECTED（业务员改后重提）。
  STATUSES = %w[DRAFT PENDING_APPROVAL APPROVED REJECTED SHIPPED CANCELLED].freeze
  KINDS = %w[PRODUCTION STOCK].freeze
  # 现货出库「提交即预占」：待审核/已审核未出库的单占用成品库存，可用=物理结存−预占。
  RESERVING_STATUSES = %w[PENDING_APPROVAL APPROVED].freeze
  # 出库时销售订单可推进到 SHIPPED 的前置状态。
  SALES_ORDER_ADVANCEABLE = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT].freeze
  SHIPMENTS_BOARD_KEY = 'mes_shipments_index'

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true # 现货出库审核人（CRM 部门主管）
  belongs_to :voided_by, class_name: 'User', optional: true
  has_many :shipment_items, class_name: 'Mes::ShipmentItem', dependent: :destroy, inverse_of: :shipment
  accepts_nested_attributes_for :shipment_items, allow_destroy: true
  has_many_attached :files

  validates :shipment_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  # 空明细的出库单没有任何意义，却会占掉单号，还会让它挂的那张销售订单永远报
  # 「已生成出库单 DN-xxx，不能重复转单」——转不动，也看不出该去删哪张。
  # 页面一次只会提交一行，碰不到这条；挡的是直接调接口建出来的空单。
  validate :items_present, on: :create

  def self.document_number_prefix = 'DN'
  def self.document_number_column = :shipment_no

  scope :reserving, -> { where(kind: 'STOCK', status: RESERVING_STATUSES) }

  # 预占量：待审核/已审核未出库的现货出库单占用的成品，按 [crm_product_id, warehouse_id] 汇总。
  # exclude_id 用于提交自身时排除本单，只看「别人」已预占多少。
  def self.reserved_qty_map(account, exclude_id: nil)
    rel = account.mes_shipment_items
                 .joins(:shipment)
                 .where(mes_shipments: { kind: 'STOCK', status: RESERVING_STATUSES })
                 .where.not(crm_product_id: nil)
    rel = rel.where.not(shipment_id: exclude_id) if exclude_id
    rel.group('mes_shipment_items.crm_product_id', 'mes_shipments.warehouse_id').sum('mes_shipment_items.qty')
  end

  def stock? = kind == 'STOCK'

  # 出库审核人＝**财务**（审「款收齐没有」）。配了「出库审核人」就只认配的人，
  # 没配回落到财务 + 管理员/副管——同原料入库那套（Mes::StockEntry.approver?）。
  APPROVER_BOARD_KEY = 'mes_shipment_approver'.freeze

  # 谁能审出库单。按人问走 approver?，取全量走 approver_ids——**两个必须同一口径**：
  # 一个管挡写和显按钮，一个管发待审核通知，分家就会出现「通知发给了 A，A 点进去 403」
  # 或者反过来（2026-10-23 之前就是反过来：通知的收件人是提交时刚被置空的 manager_id，
  # 于是八张单提交审核、一条通知都没发出去，有张单在那儿挂了一天多没人知道）。
  def self.approver_ids(account)
    configured = account.mes_board_owners.where(board_key: APPROVER_BOARD_KEY)
                        .pluck(:manager_ids).flatten.compact.uniq
    return configured if configured.any?

    # 没配审核人时回落财务 + 管理员/副管。crm_finance? 把管理员也算进财务，
    # 这里的三个条件与它展开后完全对应。
    account.account_users.active_members
           .where(role: roles_administrator)
           .or(account.account_users.active_members.where(crm_finance: true))
           .or(account.account_users.active_members.where(crm_role: 'deputy_admin'))
           .pluck(:user_id).uniq
  end

  def self.roles_administrator = AccountUser.roles[:administrator]

  def self.approver?(account, account_user)
    return false if account_user.blank?

    approver_ids(account).include?(account_user.user_id)
  end

  # 出库审批的金额闸（2026-10-21 陈总与财务定）：订单货款不超过 5000 美金 / 3 万人民币的，
  # 仓库自己批就能出货；超过才通知财务审。原先一张单等一次财务审核，出一张等一张。
  # 按近 180 天的实绩，33 张出库单里 26 张落进仓库直批，财务要审的降到 7 张。
  SELF_APPROVE_LIMITS = { 'USD' => 5_000, 'CNY' => 30_000 }.freeze

  # 这张单仓库能不能自己批。
  # 「不含运费，仅产品金额」是用户的原话——order_amount_micros 本来就不含运费（运费另存
  # shipping_micros，见 Crm::SalesOrder#gross_sales_micros），拿它正好。
  # 查不到金额的（没挂销售订单、金额空着）一律按大额走财务：这道闸是为放行小单设的，
  # 拿不准的时候不该替财务做主。
  def warehouse_self_approvable?
    order = crm_sales_order
    return false if order.nil? || order.order_amount_micros.to_i <= 0

    amount = order.order_amount_micros.to_i / 1_000_000.0
    limit = SELF_APPROVE_LIMITS[order.order_currency]
    return amount <= limit if limit

    usd = usd_amount(amount, order.order_currency)
    usd.present? && usd <= SELF_APPROVE_LIMITS['USD']
  end

  # 谁能审这张单：财务（及配置的审核人）始终能审；小额单仓库自己也能批。
  def approver_for?(account_user)
    return false if account_user.blank?
    return true if self.class.approver?(account, account_user)

    warehouse_self_approvable? && account_user.mes_can?(:shipment)
  end

  # 提交审核：等财务看「这张单的款收齐没有」。
  #
  # 用户给的金蝶流程：业务下销售订单 → 主管审核 → 推到仓库 → **财务审核是否收齐全款** → 出库。
  # 主管那道已经在销售订单上（Crm::SalesOrderApproval），所以这里不再过主管，直接到财务。
  # 两种出库都走：生产出库照样过账打 ERP（成本归集+凭证+订单完结），凭什么不审。
  # 重提（REJECTED）沿用同一路径重走审核。
  def submit_for_approval!(_actor = nil)
    raise StandardError, '当前状态无法提交审核' unless %w[DRAFT REJECTED].include?(status)

    # with_lock 锁本单 + 锁成品结存行：让「读他人预占→校验可用→落自己预占」串行化，
    # 杜绝并发提交双双通过导致的超卖。
    with_lock do
      raise StandardError, '当前状态无法提交审核' unless %w[DRAFT REJECTED].include?(status)

      # 预占是**现货出库专有**的（reserving scope 只认 STOCK）：生产出库的货是刚报完工
      # 入库的成品，不进预占池；对它按预占口径算可用量会算成负数，单子根本提交不了。
      # 出库那一刻的库存充足性由 ship! 里的 ensure_stock_sufficient! 把关，两种都跑。
      if stock?
        lock_stock_balances!
        ensure_available_for_reservation!
      end
      self.submitted_at = Time.current
      self.reject_reason = nil
      # manager_id 是历史字段名，现在存的是**审核的财务**（改名要动存量数据和前端，
      # 同采购单 gm_id 那样只换面向用户的文案）。审核人在审的时候才定——财务是一组人，
      # 谁先看到谁批，不像部门主管那样提交时就能解析出唯一一个。
      self.manager_id = nil
      update!(status: 'PENDING_APPROVAL')
    end
    notify_approval_pending if status == 'PENDING_APPROVAL'
    self
  end

  # 这张单的款收齐没有（财务审核的依据）。没挂销售订单或还没建账时返回 nil，
  # 前端据此显示「未建账，无法核对收款」而不是显示成「已收 0」吓人一跳。
  def receivable_state
    return nil if crm_sales_order.blank?

    Erp::OrderReceivableProgress.new(crm_sales_order).call
  end

  # 款是否已收齐。查不到收款信息时返回 nil（＝不知道），不要假装收齐了。
  def fully_paid?
    state = receivable_state
    return nil if state.blank?

    state[:outstanding_micros].to_i <= 0
  end

  # 财务审核通过 → 待出库，并推仓库（通知出库板块负责人备货执行）。
  #
  # 款没收齐也能放行（老客户赊账、老板特批是真实存在的），但必须写理由——
  # 硬卡住的话财务会绕过系统口头放行，留痕反而没了。
  def approve!(actor, note: nil)
    raise StandardError, '非「待审核」环节' unless status == 'PENDING_APPROVAL'
    raise StandardError, '这张单的款还没收齐，放行请写明理由' if fully_paid? == false && note.to_s.strip.blank?

    update!(status: 'APPROVED', manager_id: actor.id, approved_at: Time.current,
            approve_note: note.to_s.strip.presence)
    Mes::Notifier.resolve(account: account, kinds: 'shipment_approval_pending', title_like: shipment_no)
    notify_warehouse_ready
    self
  end

  # ── 做错了要重来：退回草稿 / 作废 ──────────────────────────────
  # CANCELLED 这个状态从一开始就在 STATUSES 里，却从来没有谁能把单置过去。
  # 结果是做错一张**待出库**的单彻底没救：删不掉（destroy 只许草稿/被驳回）、
  # 驳不回（reject! 只认待审核）、重开又撞「该订单已生成出库单 DN-xxx」。
  #
  # 预占不用手工释放：reserving scope 按状态算（只认 PENDING_APPROVAL/APPROVED），
  # 状态一离开这两个，可用现货自己就回来了。
  REVERTIBLE_STATUSES = %w[PENDING_APPROVAL APPROVED REJECTED].freeze

  # 退回草稿：单号和历史都留着，业务员改完重新提交审核——比「删了重建」更贴近
  # 「做错了要改」这件事本身。
  def revert_to_draft!(actor)
    with_lock do
      raise StandardError, revert_blocker unless REVERTIBLE_STATUSES.include?(status)

      update!(status: 'DRAFT', submitted_at: nil, manager_id: nil, approved_at: nil,
              approve_note: nil, reject_reason: nil)
    end
    Mes::Notifier.resolve(account: account, kinds: 'shipment_approval_pending', title_like: shipment_no)
    notify_owner_of_rollback("出库单退回草稿：#{shipment_no}", "#{actor_name(actor)} 把这张单退回草稿，改完请重新提交审核")
    self
  end

  # 作废：整张单不要了。置 CANCELLED 留痕（不硬删，账要查得到），
  # 作废掉的单不算重复开单（duplicate/convert 两处都排除 CANCELLED），销售订单可以重新转。
  def void!(actor, reason:)
    raise StandardError, '作废要填原因' if reason.to_s.strip.blank?

    with_lock do
      raise StandardError, revert_blocker unless REVERTIBLE_STATUSES.include?(status) || status == 'DRAFT'

      update!(status: 'CANCELLED', void_reason: reason.to_s.strip,
              voided_at: Time.current, voided_by_id: actor&.id)
    end
    Mes::Notifier.resolve(account: account, kinds: 'shipment_approval_pending', title_like: shipment_no)
    notify_owner_of_rollback("出库单已作废：#{shipment_no}", "#{actor_name(actor)} 作废了这张单，原因：#{reason.to_s.strip}")
    self
  end

  def revert_blocker
    return '已出库的单不能退回或作废，要退货请走退货流程' if status == 'SHIPPED'

    "这张单是「#{status}」，退不回也作废不了"
  end

  # 主管驳回 → 退回业务员（可改后重提）。需填原因。
  def reject!(actor, reason:)
    raise StandardError, '非「待审核」环节' unless status == 'PENDING_APPROVAL'

    update!(status: 'REJECTED', manager_id: actor.id, reject_reason: reason)
    Mes::Notifier.resolve(account: account, kinds: 'shipment_approval_pending', title_like: shipment_no)
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'shipment_rejected',
      title: "现货出库被驳回：#{shipment_no}", body: "驳回原因：#{reason}"
    )
    self
  end

  # 通知出库（XMind 节点8）：打时间戳 + 站内通知对应业务员（订单归属人）货已安排出库。
  def notify!
    update!(notified_at: Time.current)
    recipient = production_order&.owner_id || crm_sales_order&.owner_id || owner_id
    Mes::Notifier.notify(
      account: account, recipients: recipient, kind: 'shipment_notified',
      title: "出库通知：#{shipment_no}",
      body: "#{customer_label}订单已安排出库，请留意后续物流跟进。", order: production_order
    )
    self
  end

  # 出库：开成品出库 StockEntry 扣成品库存（并把生产订单推进 SHIPPED），
  # 回写来源销售订单为「已出货」。现货出库须主管审核通过（APPROVED）后仓库方可出库。
  def ship!
    # with_lock 加行锁+事务：持锁后复检状态防重复出库；再锁成品结存行后校验充足性→扣减，
    # 让「查库存→扣库存」在同一临界区，杜绝并发超卖/负库存。
    with_lock do
      # 两种出库都要财务审过才能出：过账会打 ERP（成本归集 + 收入凭证 + 回写订单完结），
      # 生产出库照样打，凭什么不审（用户给的金蝶流程：…推到仓库 → 财务审核是否收齐全款 → 出库）。
      raise StandardError, '出库单需财务审核通过后才能出库' unless status == 'APPROVED'

      lock_stock_balances!
      ensure_stock_sufficient!

      ts = Time.current
      entry = account.mes_stock_entries.create!(
        purpose: 'SHIPMENT', production_order: production_order, from_warehouse_id: warehouse_id, owner_id: owner_id,
        stock_entry_items_attributes: shipment_items.map do |item|
          { item_type: 'PRODUCT', crm_product_id: item.crm_product_id, qty: item.qty, warehouse_id: warehouse_id }
        end
      )
      entry.post!
      update_columns(status: 'SHIPPED', shipped_at: ts, updated_at: ts)
      writeback_sales_order(ts)
      rollup_erp_stock_cost(entry)
    end
    # 凭证放在事务外：成本归集要先落 erp_order_costs，成本凭证才取得到金额；
    # 而且写凭证不该占着出库单的行锁。失败只记日志——ERP 不能挡住仓库出库。
    generate_erp_vouchers
    Mes::Notifier.resolve(account: account, kinds: 'shipment_approved', title_like: shipment_no)
    self
  end

  private

  def actor_name(actor)
    actor&.crm_display_name.presence || '有人'
  end

  # 退回/作废都要让开单的业务员知道——单子不在他那儿了，不通知他会一直等审核结果。
  def notify_owner_of_rollback(title, body)
    return if owner_id.blank?

    Mes::Notifier.notify(account: account, recipients: owner_id, kind: 'shipment_rejected',
                         title: title, body: body)
  end

  # 两套阈值不是同一个汇率关系（5000 美金 ≈ 3.6 万人民币，而人民币线是 3 万），所以不能
  # 统一折一种币比。USD/CNY 各比各的，其余币种（生产上只有 2 张 EUR）折成美金比 5000。
  # rate_for 给的是 CNY / 1 单位，两边同除以美金牌价即得美金额。
  def usd_amount(amount, currency)
    rate = Crm::FxRate.rate_for(currency, Date.current)
    usd_rate = Crm::FxRate.rate_for('USD', Date.current)
    return nil if rate.blank? || usd_rate.to_d.zero?

    amount * rate.to_d / usd_rate.to_d
  end

  def items_present
    errors.add(:base, '出库单至少要有一行明细') if shipment_items.reject(&:marked_for_destruction?).empty?
  end

  # 现货出库的成本＝该出库单 FIFO 耗掉的批次层金额，挂到销售订单上（库存单轨道的成本来源）。
  # 定制单不走这里——它的成本已由 CostRollupService 按领料/外协归集，再挂一次就翻倍。
  # ERP 不能挡住仓库出库，异常只记日志。
  def rollup_erp_stock_cost(entry)
    Erp::StockCostService.new(account).attribute_shipment!(self, entry)
  rescue StandardError => e
    Rails.logger.error("[Erp::StockCost] 出库单 #{shipment_no} 成本归集失败: #{e.message}")
  end

  # 销售出库出两张待过账凭证：收入（借应收/贷收入+销项税）与成本结转（借主营业务成本/贷库存商品）。
  # 口径见 ERP_SPEC §8.2bis。两张分开是财务要的（「销售出库有两笔凭证」）。
  def generate_erp_vouchers
    service = Erp::AutoVoucherService.new(account)
    service.for_shipment_revenue(self)
    service.for_shipment_cost(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::AutoVoucher] 出库单 #{shipment_no} 生成凭证失败: #{e.message}")
  end

  def product_line_source = production_order

  def writeback_sales_order(timestamp)
    return if crm_sales_order.nil?
    return unless SALES_ORDER_ADVANCEABLE.include?(crm_sales_order.status)

    crm_sales_order.update_columns(status: 'SHIPPED', updated_at: timestamp)
    sync_order_completion
  end

  # 先款后货（PI 付款转订单）的单子出货时钱早收清了，这里补判一次直接推到完结。
  # ERP 是下游，出不了货比记不上账严重，所以异常只记日志不往上抛。
  def sync_order_completion
    Erp::OrderCompletionService.new(account).sync!(crm_sales_order.reload)
  rescue StandardError => e
    Rails.logger.error("[Erp::OrderCompletion] 出库单 #{shipment_no} 回写订单完结失败: #{e.message}")
  end

  # 锁定本单涉及的成品结存行（SELECT ... FOR UPDATE），使预占/出库的「查—扣」在同一临界区串行。
  def lock_stock_balances!
    ids = shipment_items.filter_map do |item|
      account.mes_stock_balances
             .where(item_type: 'PRODUCT', crm_product_id: item.crm_product_id, warehouse_id: warehouse_id)
             .pick(:id)
    end
    account.mes_stock_balances.where(id: ids).lock(true).load if ids.any?
  end

  # 无部门主管时的兜底审批人=绩效设置里的总经理（须非本人），避免「零审批直发」的控制失效。
  def fallback_gm_approver_id
    gm = Crm::PerformanceSetting.for_account(account)&.gm_owner_id
    gm if gm.present? && gm != owner_id
  end

  # 库存不足拦截：逐行校验成品仓结存 ≥ 出库量，不足报错列出缺口（正/现货出库均适用，杜绝负库存）。
  def ensure_stock_sufficient!
    shortages = shipment_items.filter_map do |item|
      balance = account.mes_stock_balances.find_by(
        item_type: 'PRODUCT', crm_product_id: item.crm_product_id, warehouse_id: warehouse_id
      )
      on_hand = balance&.qty.to_d
      next if on_hand >= item.qty.to_d

      "#{item.crm_product&.name || "成品##{item.crm_product_id}"}（现货 #{fnum(on_hand)}，需 #{fnum(item.qty)}）"
    end
    raise StandardError, "成品库存不足，无法出库：#{shortages.join('；')}" if shortages.any?
  end

  # 提交预占校验：可用（物理结存 − 其他待出库单已预占）≥ 本单出库量，否则拦截，防多人抢同一批现货。
  def ensure_available_for_reservation!
    reserved = self.class.reserved_qty_map(account, exclude_id: id)
    shortages = shipment_items.filter_map { |item| reservation_shortage(item, reserved) }
    raise StandardError, "可用现货不足（已被其他待出库单预占），无法提交：#{shortages.join('；')}" if shortages.any?
  end

  def reservation_shortage(item, reserved)
    balance = account.mes_stock_balances.find_by(
      item_type: 'PRODUCT', crm_product_id: item.crm_product_id, warehouse_id: warehouse_id
    )
    available = balance&.qty.to_d - reserved[[item.crm_product_id, warehouse_id]].to_d
    return if available >= item.qty.to_d

    "#{item.crm_product&.name || "成品##{item.crm_product_id}"}（可用 #{fnum(available)}，需 #{fnum(item.qty)}）"
  end

  # 现货出库审核人=业务员所属（主）部门负责人；本人即负责人则向上找上级部门负责人。
  def resolve_manager_id
    return nil if owner_id.nil?

    membership = account.org_memberships.where(user_id: owner_id).order(is_primary: :desc, id: :asc).first
    dept = membership && account.org_departments.find_by(id: membership.department_id)
    while dept
      return dept.leader_id if dept.leader_id.present? && dept.leader_id != owner_id

      dept = dept.parent_id && account.org_departments.find_by(id: dept.parent_id)
    end
    nil
  end

  # 无部门主管时：跳过审核直接进「待出库」并推仓库。
  def approve_without_manager!
    update!(status: 'APPROVED', approved_at: Time.current)
    notify_warehouse_ready
  end

  # 待审核通知的收件人 = **这张单实际能审的人**，与 approver_for? 同一口径。
  # 小额单仓库自己批（2026-10-21 定的金额闸），就别再去吵财务——那道闸本来就是
  # 为了把 33 张里的 26 张从财务台上拿走的，照样通知等于白设。
  def approval_notify_ids
    ids = if warehouse_self_approvable?
            account.mes_board_owners.find_by(board_key: SHIPMENTS_BOARD_KEY)&.manager_ids || []
          else
            self.class.approver_ids(account)
          end
    ids = (ids.map(&:to_i) - [owner_id]).uniq # 自己提交的单不用通知自己
    # 兜底：算下来一个人都没有（板块负责人没配、或唯一的负责人正好就是提交人自己——
    # 生产上出库板块负责人就是提交这张单的人）时回落到审核人组。这张单照样等着人审，
    # 宁可多吵一个人，也绝不能又变成「通知零人」。
    ids.presence || (self.class.approver_ids(account) - [owner_id]).uniq
  end

  def notify_approval_pending
    who = warehouse_self_approvable? ? '仓库' : '财务'
    Mes::Notifier.notify(
      account: account, recipients: approval_notify_ids, kind: 'shipment_approval_pending',
      title: "待审核：#{stock? ? '现货' : '生产'}出库 #{shipment_no}",
      body: "#{owner&.name || '业务员'} 提交了出库单，待你（#{who}）审核。",
      order: production_order
    )
  end

  # 推仓库：通知出库板块负责人（仓管）备货执行。
  def notify_warehouse_ready
    recipients = account.mes_board_owners.find_by(board_key: SHIPMENTS_BOARD_KEY)&.manager_ids || []
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'shipment_approved',
      title: "待出库：现货出库 #{shipment_no}",
      body: "#{customer_label}现货出库单已审核通过，请仓库出库。"
    )
  end

  def customer_label
    name = crm_customer&.name
    name.present? ? "#{name} 的" : ''
  end

  # 数量文案：去掉多余小数（50.0 → 50）。
  def fnum(value)
    format('%g', value.to_f)
  end
end
