# == Schema Information
#
# Table name: mes_stock_entries
#
#  id                        :bigint           not null, primary key
#  actual_inbound_date       :datetime
#  approval_status           :string           default("APPROVED"), not null
#  approved_at               :datetime
#  color                     :string
#  entry_no                  :string           not null
#  extra_purchase_order_ids  :bigint           default([]), not null, is an Array
#  is_checked                :boolean          default(FALSE), not null
#  posted_at                 :datetime
#  print_count               :integer          default(0), not null
#  product_line              :string
#  purpose                   :string           not null
#  reject_reason             :text
#  remark                    :text
#  status                    :string           default("DRAFT"), not null
#  warehouse_confirmed_at    :datetime
#  workshop_confirmed_at     :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  approved_by_id            :bigint
#  checked_by_id             :bigint
#  from_warehouse_id         :bigint
#  owner_id                  :bigint
#  production_order_id       :bigint
#  purchase_order_id         :bigint
#  received_by_id            :bigint
#  to_warehouse_id           :bigint
#  warehouse_confirmed_by_id :bigint
#  workshop_confirmed_by_id  :bigint
#
# Indexes
#
#  index_mes_stock_entries_on_account_and_approval       (account_id,approval_status)
#  index_mes_stock_entries_on_account_and_product_line   (account_id,product_line)
#  index_mes_stock_entries_on_account_id                 (account_id)
#  index_mes_stock_entries_on_account_id_and_entry_no    (account_id,entry_no) UNIQUE
#  index_mes_stock_entries_on_account_id_and_purpose     (account_id,purpose)
#  index_mes_stock_entries_on_extra_purchase_order_ids   (extra_purchase_order_ids) USING gin
#  index_mes_stock_entries_on_owner_id                   (owner_id)
#  index_mes_stock_entries_on_production_order_id        (production_order_id)
#  index_mes_stock_entries_on_purchase_order_id          (purchase_order_id)
#  index_mes_stock_entries_on_warehouse_confirmed_by_id  (warehouse_confirmed_by_id)
#  index_mes_stock_entries_on_workshop_confirmed_by_id   (workshop_confirmed_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => nullify
#  fk_rails_...  (warehouse_confirmed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (workshop_confirmed_by_id => users.id) ON DELETE => nullify
#
class Mes::StockEntry < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  include Mes::Returnable

  # 一表多用（ERPNext Stock Entry 模式）。SHIPMENT=成品出库（销售出库开单时内部生成）。
  #
  # OPENING=期初库存：上线前仓库里实际存在、却没走过系统采购的货。
  # 不走 MATERIAL_RECEIPT 是因为那条路过账会出「借存货/贷应付账款」的凭证，
  # 给谁都不是的供应商凭空挂一笔应付。期初只加结存、记流水，不出凭证、不绑生产订单、
  # 不推阶段（故 FLOW_MIN_STAGE / STAGE_ADVANCE / PAYABLE_VOUCHER_PURPOSES 都不收录它），
  # 成本层也不建——成品的 FIFO 期初要带单价，走 Erp::StockOpeningImportService 单独导。
  PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_ISSUE MATERIAL_RETURN MANUFACTURE SCRAP SHIPMENT OPENING].freeze
  IN_PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_RETURN MANUFACTURE OPENING].freeze
  STATUSES = %w[DRAFT POSTED CANCELLED].freeze

  # 过账前的财务审核闸。2026-10-21 财务与仓库约定**原料入库不再逐单审批**：仓管自行
  # 过账，月底把送货单整叠转给财务核对——一张单等一次审核，生产上 40 张入库单就这么
  # 卡在「待审核」上。清空这个清单即整条闸失效（needs_approval? 恒 false，过账按钮不再
  # 禁用、审核/驳回按钮不再出现），审核机制本身留着：流程要收回去，把 purpose 填回来即可。
  APPROVAL_STATUSES = %w[PENDING APPROVED REJECTED].freeze
  APPROVAL_REQUIRED_PURPOSES = [].freeze
  # 审核人按产品线配置，复用 Mes::BoardOwner（同采购审批人那套，见 Mes::PurchaseOrder）。
  APPROVER_BOARD_KEY = 'mes_stock_approver'.freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', optional: true

  # 本单关联的全部采购单 id（主单 + 追加的）。同一家供应商同一天送来好几张单的料，
  # 仓管一次收完比开三张入库单省事（照采购单挂多张生产订单那套，见 Mes::PurchaseOrder）。
  def all_purchase_order_ids
    ([purchase_order_id] + extra_purchase_order_ids.to_a).compact.uniq
  end

  def related_purchase_orders
    account.mes_purchase_orders.where(id: all_purchase_order_ids).order(:id)
  end
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :checked_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :received_by, class_name: 'User', optional: true
  belongs_to :workshop_confirmed_by, class_name: 'User', optional: true
  belongs_to :warehouse_confirmed_by, class_name: 'User', optional: true
  has_many :stock_entry_items, class_name: 'Mes::StockEntryItem', dependent: :destroy, inverse_of: :stock_entry
  accepts_nested_attributes_for :stock_entry_items, allow_destroy: true

  # 收货单留证（原料入库必传，校验在控制器）。
  has_many_attached :receipts

  validates :entry_no, presence: true, uniqueness: { scope: :account_id }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :status, inclusion: { in: STATUSES }
  validate :enforce_flow_prerequisite, on: :create
  # 建单当场拦重复/超量成品入库：当面说清「已入 X/Y」，而不是放它存下去、几天后在仓管那儿爆。
  validate :enforce_fg_inbound_quota, on: :create

  # ── 流程硬锁 ──：下游库存单必须等生产订单走到对应阶段才能开单，前面工序没做完后端直接拒绝。
  #   原料入库→须已采购；生产领料→须原料已入库；成品入库→须已领料+进入生产(报工)。
  #   外购订单只走 采购→收货入成品仓→出库，禁止生产领料/成品入库。
  FLOW_MIN_STAGE = {
    'MATERIAL_RECEIPT' => 'PURCHASING',
    'MATERIAL_ISSUE' => 'MATERIAL_INBOUND',
    'MANUFACTURE' => 'PRODUCTION'
  }.freeze
  FLOW_PREREQ_LABEL = {
    'MATERIAL_RECEIPT' => '采购下单',
    'MATERIAL_ISSUE' => '原料入库',
    'MANUFACTURE' => '生产领料、生产报工'
  }.freeze
  OUTSOURCE_FORBIDDEN_PURPOSES = %w[MATERIAL_ISSUE MANUFACTURE].freeze

  before_create :stamp_workshop_confirm
  before_create :stamp_pending_approval
  before_update :reopen_approval_on_edit
  after_create :notify_warehouse_count_pending

  scope :posted, -> { where(status: 'POSTED') }

  def self.document_number_prefix = 'SE'
  def self.document_number_column = :entry_no

  # ── 单据退回（Mes::Returnable）──：库存单一表多用，本板块与上游按 purpose 而定。
  #   原料入库(MATERIAL_RECEIPT) → 上游=采购；生产领料(MATERIAL_ISSUE) → 上游=原料入库；
  #   成品入库(MANUFACTURE) → 上游=生产报工。
  RETURN_BOARD_BY_PURPOSE = {
    'MATERIAL_RECEIPT' => 'mes_stock_entries_index',
    'MATERIAL_ISSUE' => 'mes_material_issues_index',
    'MANUFACTURE' => 'mes_fg_inbound_index'
  }.freeze
  RETURN_LABEL_BY_PURPOSE = {
    'MATERIAL_RECEIPT' => '原料入库单',
    'MATERIAL_ISSUE' => '生产领料单',
    'MANUFACTURE' => '成品入库单'
  }.freeze

  def document_board_key = RETURN_BOARD_BY_PURPOSE[purpose] || 'mes_stock_entries_index'
  def return_document_label = RETURN_LABEL_BY_PURPOSE[purpose] || '库存单'
  def return_document_no = entry_no
  # 只有未过账(DRAFT)的库存单可退回；已过账写了不可改的库存流水，要撤须走冲销。
  def returnable? = status == 'DRAFT' && RETURN_BOARD_BY_PURPOSE.key?(purpose)

  # ── 成品入库交接闸 ──：车间（report）开单=交接发起、自动盖车间章；
  # 仓库（stock）清点数量确认=盖仓库章并直接过账入库。
  def dual_confirm_required? = purpose == 'MANUFACTURE'
  def dual_confirmed? = workshop_confirmed_at.present? && warehouse_confirmed_at.present?

  # 仓库清点确认：盖仓库章后直接过账（确认即入库生效）。
  # 这张单要不要走审核。成品入库/领料/报废那些不走。
  def needs_approval? = APPROVAL_REQUIRED_PURPOSES.include?(purpose)

  def approved? = !needs_approval? || approval_status == 'APPROVED'

  # 过账前的审核闸。拦住就把原因原话抛给前端，别让仓管对着一个灰按钮猜。
  def approval_blocker
    return nil if approved?
    return '这张入库单被驳回了，改完会自动回到待审核，等财务重新审核' if approval_status == 'REJECTED'

    '这张入库单还没经财务审核，审核通过才能过账'
  end

  def approve!(actor)
    with_lock do
      raise StandardError, '这张单不需要审核' unless needs_approval?
      raise StandardError, '已经审核通过了' if approval_status == 'APPROVED'

      update!(approval_status: 'APPROVED', approved_by: actor, approved_at: Time.current, reject_reason: nil)
    end
    self
  end

  def reject!(actor, reason)
    raise StandardError, '驳回要填原因' if reason.to_s.strip.blank?

    with_lock do
      raise StandardError, '这张单不需要审核' unless needs_approval?
      raise StandardError, '已过账的单不能驳回，请用「作废」冲销' if status == 'POSTED'

      update!(approval_status: 'REJECTED', approved_by: actor, approved_at: Time.current,
              reject_reason: reason.to_s.strip)
    end
    self
  end

  # 谁能审：配了审核人就只认配置的那些人；没配就回落到财务（用户原话「入库单由财务审核」），
  # 管理员/副管理员一直都能兜底。这样不配也能用，配了就收紧。
  def self.approver?(account, account_user)
    return false if account_user.blank?

    configured = account.mes_board_owners.where(board_key: APPROVER_BOARD_KEY)
                        .pluck(:manager_ids).flatten.compact.uniq
    return configured.include?(account_user.user_id) if configured.any?

    account_user.administrator? || account_user.crm_deputy_admin? || account_user.crm_finance?
  end

  def confirm_warehouse!(actor)
    raise StandardError, '仅成品入库单需要仓库清点确认' unless dual_confirm_required?
    raise StandardError, '单据已过账或已作废，无法确认' unless status == 'DRAFT'
    raise StandardError, '仓库已清点确认，无需重复' if warehouse_confirmed_at.present?

    update!(warehouse_confirmed_at: Time.current, warehouse_confirmed_by_id: actor&.id)
    post!
    self
  end

  # 过账：按 purpose 方向对每个明细刷结存、记流水，然后置 POSTED。
  # 原料入库过账把关联生产订单推进到「原料入库」阶段。
  def post!
    # with_lock 加行锁并开事务：持锁后重新校验状态，杜绝并发/双击重复过账（结存、收货量翻倍）。
    with_lock do
      raise StandardError, '单据已过账或已作废' unless status == 'DRAFT'
      raise StandardError, approval_blocker if approval_blocker
      raise StandardError, '成品入库需车间负责人与仓管共同确认后方可过账' if dual_confirm_required? && !dual_confirmed?

      ensure_purchase_orders_approved!

      # 成品入库防超量在并发下失效——锁住生产订单，让「读累计→校验→写入」在同一临界区。
      production_order&.lock! if purpose == 'MANUFACTURE'
      ensure_no_fg_over_inbound!
      # 出库方向(领料/报废/出库)过账前校验结存充足，杜绝超领→负库存。
      ensure_stock_available_for_out!

      ts = Time.current
      stock_entry_items.each { |item| post_item(item, ts) }
      update_columns(status: 'POSTED', posted_at: ts, updated_at: ts)
      sync_purchase_receipt! if purpose == 'MATERIAL_RECEIPT' && purchase_order_id.present?
      advance_production_order_on_receipt(ts)
      complete_production_order_if_fg_full(ts)
      complete_production_order_if_shipped(ts)
      sync_erp_stock_cost
    end
    # 采购入库/退货出应付凭证（借 存货科目 / 贷 应付账款，退货红字）。放事务外同出库单。
    generate_erp_receipt_voucher
    # 应付台账不在这里起账了（2026-10-21）：财务定的流程是**先跟供应商对账、对好了再建账**，
    # 收货即建账会把还没核对的数字先摆进欠款里。这一笔现在进应付管理的「待对账」清单
    # （Erp::LedgerBuilderService#pending_reconciliation 按已过账收货实时算），
    # 财务确认后才落台账。凭证照出——那是总账口径，与业务账的对账流程互不等待。
    self
  end

  # 采购入库与采购退货生成待过账的应付凭证（口径见 ERP_SPEC §8.2bis）。
  # 其它用途（领料/成品入库/报废/销售出库）不在此列：
  # 领料与成品入库是存货内部结转、销售出库的凭证由出库单自己出。
  PAYABLE_VOUCHER_PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_RETURN].freeze

  def generate_erp_receipt_voucher
    return unless PAYABLE_VOUCHER_PURPOSES.include?(purpose)

    Erp::AutoVoucherService.new(account).for_stock_receipt(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::AutoVoucher] 出入库单 #{entry_no} 生成凭证失败: #{e.message}")
  end

  # 作废（冲销）：把过账时扣/加的库存按反方向冲回、记反向流水，已过账才可作废；
  # 若关联生产订单仍停在本单推进到的阶段且无其它已过账领料单，则回退一阶段。保留单据（置 CANCELLED）可追溯。
  def cancel!
    with_lock do
      raise StandardError, '单据尚未过账，草稿可直接删除、无需作废' unless status == 'POSTED'

      ts = Time.current
      stock_entry_items.each { |item| move_stock!(item, ts, -direction_sign) }
      # 作废原料入库：对称回退采购单收货量与在途（正向 sync_purchase_receipt! 累加过，作废须冲回）。
      reverse_purchase_receipt! if purpose == 'MATERIAL_RECEIPT' && purchase_order_id.present?
      revert_production_order_stage_on_void(ts)
      # 存货层回滚：入库撤层、出库还层。这里**不吞异常**——「已出库的入库单不许作废」是
      # 成本正确性的硬闸，吞掉就会让层被撤掉、后续出库拿错成本。
      Erp::StockCostService.new(account).reverse_entry!(self)
      update_columns(status: 'CANCELLED', updated_at: ts)
    end
    self
  end

  private

  # 成品存货 FIFO：入库建批次层、出库按先进先出逐层扣（金额只落 erp_* 表，MES 不持有金额）。
  # ERP 是下游，不能反过来挡住仓库过账，所以过账路径上的异常只记日志——
  # 层缺了财务在存货页看得见，可手工补层；作废路径则不吞（见 cancel!）。
  def sync_erp_stock_cost
    Erp::StockCostService.new(account).sync_entry!(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::StockCost] 库存单 #{entry_no} 成本核算失败: #{e.message}")
  end

  # 流程硬锁校验：越级开下游单直接拦下（前端也会隐藏不可选订单，此处为后端兜底）。
  def enforce_flow_prerequisite
    return unless FLOW_MIN_STAGE.key?(purpose)

    po = production_order
    return if po.nil? # 无生产订单的临时库存单（如外购成品备货收货、盘盈）不受脊柱闸约束

    doc = RETURN_LABEL_BY_PURPOSE[purpose] || '库存单'
    if po.outsourced? && OUTSOURCE_FORBIDDEN_PURPOSES.include?(purpose)
      return errors.add(:base, "外购订单不做#{doc}：外购成品经「采购 → 收货」直接入成品仓")
    end
    return if po.stage_reached?(FLOW_MIN_STAGE[purpose])

    stage_cn = Mes::ProductionOrder::STAGE_LABELS[po.stage] || po.stage
    errors.add(:base, "生产订单当前在「#{stage_cn}」阶段，需先完成#{FLOW_PREREQ_LABEL[purpose]}才能开#{doc}")
  end

  # 成品入库防重复/防超量：同一生产订单已过账入库累计 + 本单成品量不得超过订单数量。
  # 收齐后再开 → 「已收齐不能重复入库」；未收齐但本次超出剩余 → 「不能超量入库」。
  # 仅约束成品入库(MANUFACTURE)且挂了生产订单的单据；其余库存单不受影响。
  def enforce_fg_inbound_quota
    msg = fg_over_inbound_error
    errors.add(:base, msg) if msg
  end

  def ensure_no_fg_over_inbound!
    msg = fg_over_inbound_error
    raise StandardError, msg if msg
  end

  # 超量原因（无问题返回 nil）。建单校验与过账闸共用——
  # 只在过账拦是不够的：建单在车间、过账在仓库，中间隔着好几天，
  # 车间把单建出来就以为交接完了，错误却出现在几天后仓管的屏幕上，
  # 两头都不知道发生了什么（生产上因此积了 6 张永远过不了账的重复单）。
  def fg_over_inbound_error
    return nil unless purpose == 'MANUFACTURE'

    po = production_order
    return nil if po.nil? || po.qty.to_d <= 0

    already = po.fg_inbound_qty # 已过账累计（不含本张草稿）
    remaining = po.qty.to_d - already
    # 用 effective_qty(实收优先)与真实刷库口径一致，防「实收>计划」时按 qty 判定通过却超量入库。
    incoming = stock_entry_items.select { |i| i.item_type == 'PRODUCT' }.sum { |i| i.effective_qty.to_d }

    if remaining <= 0
      "该订单成品已入库收齐（#{fnum(already)}/#{fnum(po.qty)}），不能重复入库"
    elsif incoming > remaining
      "入库数量超出订单剩余（订单 #{fnum(po.qty)}，已入 #{fnum(already)}，剩 #{fnum(remaining)}，本次 #{fnum(incoming)}），不能超量入库"
    end
  end

  def fnum(value)
    format('%g', value.to_f)
  end

  def product_line_source = production_order || purchase_order

  # 车间开单即视为车间确认（开单人盖章）。
  # 被驳回的单改完自动回到「待审核」，不用仓管再找一个「重新提交」按钮
  # （驳回原因留着，财务能看出上一轮是为什么退的）。
  # 审核动作自己改 approval_status，不能被这里又翻回去。
  def reopen_approval_on_edit
    return unless approval_status == 'REJECTED' && !approval_status_changed?
    return if (changes.keys - %w[updated_at]).empty?

    self.approval_status = 'PENDING'
  end

  # 建单即「待审核」。原料入库没有草稿/提交两步——单子开出来就是等财务看的那张，
  # 再多一次「提交」点击只会多一步没人记得做的操作。
  def stamp_pending_approval
    self.approval_status = needs_approval? ? 'PENDING' : 'APPROVED'
  end

  def stamp_workshop_confirm
    return unless dual_confirm_required?

    self.workshop_confirmed_at ||= Time.current
    self.workshop_confirmed_by_id ||= owner_id
  end

  # 车间开成品入库单后通知仓库（成品入库板块负责人）清点确认。
  def notify_warehouse_count_pending
    return unless dual_confirm_required?

    recipients = account.mes_board_owners.find_by(board_key: 'mes_fg_inbound_index')&.manager_ids || []
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'fg_count_pending',
      title: "成品入库待仓库清点：#{entry_no}",
      body: "#{owner&.name || '车间'}已开成品入库单#{production_order ? "（#{production_order.order_no}）" : ''}，请仓库清点数量确认入库。",
      order: production_order
    )
  end

  def post_item(item, timestamp)
    balance_after = move_stock!(item, timestamp, direction_sign)
    # 出库兜底：持锁扣减后结存为负=超领/超发，抛错回滚整单(领料/报废/出库),杜绝负库存。
    return unless direction_sign == -1 && balance_after.negative?

    raise StandardError, "#{item_display_name(item)} 库存不足（扣减后结存 #{fnum(balance_after)}），无法过账"
  end

  # 单条明细刷结存 + 记流水，返回扣减后结存。sign=direction_sign 为过账，-direction_sign 为作废冲销。
  def move_stock!(item, timestamp, sign)
    warehouse_id = item.warehouse_id || default_warehouse_id
    raise StandardError, "明细缺仓库（#{item.item_type}）" if warehouse_id.nil?

    delta = sign * item.effective_qty
    balance_after = Mes::StockBalance.apply!(
      account_id: account_id, item_type: item.item_type, warehouse_id: warehouse_id,
      mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id, delta: delta
    )
    account.mes_stock_ledgers.create!(
      item_type: item.item_type, mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id,
      warehouse_id: warehouse_id, stock_entry_id: id, qty_change: delta, balance_after: balance_after, posted_at: timestamp
    )
    balance_after
  end

  def item_display_name(item)
    item.mes_material&.name || item.crm_product&.name || "物料##{item.mes_material_id || item.crm_product_id}"
  end

  # 出库(领料/报废/出库)过账前预检结存充足，一次性列出所有缺料，避免超领把库存刷成负数。
  def ensure_stock_available_for_out!
    return unless direction_sign == -1

    shortages = stock_entry_items.filter_map do |item|
      wh = item.warehouse_id || default_warehouse_id
      bal = account.mes_stock_balances.find_by(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, warehouse_id: wh
      )
      on_hand = bal&.qty.to_d
      next if on_hand >= item.effective_qty.to_d

      "#{item_display_name(item)}（结存 #{fnum(on_hand)}，需 #{fnum(item.effective_qty)}）"
    end
    raise StandardError, "库存不足，无法出库：#{shortages.join('；')}" if shortages.any?
  end

  # 作废回退阶段：仅当生产订单仍停在本单过账时推进到的阶段（to_stage）、
  # 且该订单已无其它已过账同类单据时，回退一阶段；否则不动（避免误退已推进的订单）。
  def revert_production_order_stage_on_void(timestamp)
    return if production_order.nil?

    # 外购按单：收货过账时从「采购」直推「成品入库」（短脊柱），作废须对称退回「采购」。
    if production_order.is_outsourced && purpose == 'MATERIAL_RECEIPT' && production_order.stage == 'FG_INBOUND'
      others = account.mes_stock_entries
                      .where(production_order_id: production_order_id, purpose: 'MATERIAL_RECEIPT', status: 'POSTED')
                      .where.not(id: id).exists?
      return if others

      production_order.update_columns(status: 'IN_PROGRESS', updated_at: timestamp) if production_order.status == 'COMPLETED'
      return production_order.enter_stage!('PURCHASING', at: timestamp)
    end

    from_stage, to_stage = STAGE_ADVANCE[purpose]
    return if from_stage.nil?
    return if production_order.stage != to_stage

    others_posted = account.mes_stock_entries
                           .where(production_order_id: production_order_id, purpose: purpose, status: 'POSTED')
                           .where.not(id: id).exists?
    return if others_posted

    # 完工入库作废回退：把「生产完成」退回「进行中」，与 fg_inbound 收齐标记对称。
    if purpose == 'MANUFACTURE' && production_order.status == 'COMPLETED'
      production_order.update_columns(status: 'IN_PROGRESS',
                                      updated_at: timestamp)
    end
    production_order.enter_stage!(from_stage, at: timestamp)
  end

  def direction_sign
    IN_PURPOSES.include?(purpose) ? 1 : -1
  end

  def default_warehouse_id
    IN_PURPOSES.include?(purpose) ? to_warehouse_id : from_warehouse_id
  end

  # 过账按 purpose 推进关联生产订单阶段（仅当处于前置阶段，避免回退/越级）。
  STAGE_ADVANCE = {
    'MATERIAL_RECEIPT' => %w[PURCHASING MATERIAL_INBOUND],
    'MATERIAL_ISSUE' => %w[MATERIAL_INBOUND PICKING],
    'MANUFACTURE' => %w[PRODUCTION FG_INBOUND],
    'SHIPMENT' => %w[FG_INBOUND SHIPPED]
  }.freeze

  def advance_production_order_on_receipt(timestamp)
    from_stage, to_stage = STAGE_ADVANCE[purpose]
    return if from_stage.nil? || production_order.nil?

    # 外购按单：成品到货收货（MATERIAL_RECEIPT）从「采购」直推「成品入库」，
    # 跳过原料入库/领料/报工（短版脊柱）。外购单条脊柱，不受齐套闸约束。
    if production_order.is_outsourced && purpose == 'MATERIAL_RECEIPT' && production_order.stage == 'PURCHASING'
      return production_order.enter_stage!('FG_INBOUND', at: timestamp)
    end

    return if production_order.stage != from_stage

    # 齐套闸：采购原料→原料入库，需本单所有关联采购单都到料齐（一单多采购单主料/辅料分采购）。
    # 未齐套则先按料到料回写、订单留在「采购原料」，等最后一张采购单到齐才推进。
    return if purpose == 'MATERIAL_RECEIPT' && !production_order.purchase_complete?

    production_order.enter_stage!(to_stage, at: timestamp)
  end

  # 完工入库收齐 → 标记「生产完成·待出库」，成品入库阶段即显示完成（不必等出库）。
  # 独立于阶段推进：分批入库时订单已在成品入库阶段，仍要在最后一批收齐时标记完成。
  def complete_production_order_if_fg_full(timestamp)
    return unless purpose == 'MANUFACTURE'

    po = production_order
    return if po.nil? || po.status != 'IN_PROGRESS'
    return unless po.stage == 'FG_INBOUND' && po.fg_inbound_complete?

    po.update_columns(status: 'COMPLETED', updated_at: timestamp)
  end

  # 成品出库过账 → 订单已发货交付，置「已完成」（SHIPPED 为终态，退出「进行中」）。
  # 兜底直接出库（未经成品入库收齐标记）的订单：出库后仍卡在 IN_PROGRESS 的问题。
  def complete_production_order_if_shipped(timestamp)
    return unless purpose == 'SHIPMENT'

    po = production_order
    return if po.nil? || po.status != 'IN_PROGRESS'
    return unless po.stage == 'SHIPPED'

    po.update_columns(status: 'COMPLETED', updated_at: timestamp)
  end

  # 原料入库过账：按物料把本次收货量累加回采购单明细 received_qty、回填实际到料日期，并重算收货状态。
  # 修复历史遗留（received_qty 从不回写，导致「按采购单收货」剩余量预填失效）+ 支撑齐套判定。
  # 实际到料 = 本次入库日期（首次到料自动填，分批到料覆盖为最近一次；采购员仍可在采购单上手动改）。
  # 本次到料日期：入库单填了实际入库日就用它，否则用过账当下。
  def receipt_arrival_at = actual_inbound_date || Time.current

  # 关联采购单必须审批通过才能收货，杜绝未审批/被驳回的采购单被越权收货推进流程。
  # 追加的那几张也要查：只看主单的话，没批的单能借一张已批的主单把货收进来。
  def ensure_purchase_orders_approved!
    return unless purpose == 'MATERIAL_RECEIPT'

    unapproved = related_purchase_orders.reject(&:approved?)
    return if unapproved.empty?

    raise StandardError, "关联采购单 #{unapproved.map(&:po_no).join('、')} 未审批通过，不能收货"
  end

  # 回写要覆盖**本单关联的每一张采购单**（主单 + 追加的）。
  # 只认主单的话，追加那张单的料收了也不记账：received_qty 不涨、收货状态永远「未收」、
  # 在途量不冲减，下次建入库单这些料还会被当成没收完再铺一遍。
  def sync_purchase_receipt!
    arrival = receipt_arrival_at
    orders = related_purchase_orders.to_a
    stock_entry_items.each do |item|
      po, po_item = locate_purchase_item(orders, item)
      next if po_item.nil?

      po_item.update_columns(
        received_qty: po_item.received_qty.to_d + item.effective_qty,
        arrival_date: arrival
      )
      # 到货冲减采购单在途（已订购未到货）量——收多少冲多少（仅审批通过、累加过在途的单）。
      next unless po.approved?

      po.reduce_on_order_for(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, qty: item.effective_qty
      )
    end
    orders.each { |o| o.reload.recompute_receipt_status! }
  end

  # 同一颗料可能在好几张关联采购单上都有（主料辅料分单下的）。
  # 优先回写「还没收完」的那张——否则收货量全记到已经收满的单上，
  # 真正欠货的那张永远显示没到货。
  def locate_purchase_item(orders, item)
    matches = orders.filter_map do |po|
      hit = po.purchase_items.find { |pi| same_material?(pi, item) }
      [po, hit] if hit
    end
    matches.find { |(_po, pi)| pi.qty.to_d > pi.received_qty.to_d } || matches.first || [nil, nil]
  end

  def same_material?(purchase_item, entry_item)
    (entry_item.mes_material_id && purchase_item.mes_material_id == entry_item.mes_material_id) ||
      (entry_item.crm_product_id && purchase_item.crm_product_id == entry_item.crm_product_id)
  end

  # 作废原料入库的对称冲销：把本单收货量从采购明细 received_qty 扣回（下限 0），
  # 并把在途量补回（reduce_on_order_for 传负数 = 回加在途），最后重算采购收货状态。
  def reverse_purchase_receipt!
    po = purchase_order
    stock_entry_items.each do |item|
      po_item = po.purchase_items.find do |pi|
        (item.mes_material_id && pi.mes_material_id == item.mes_material_id) ||
          (item.crm_product_id && pi.crm_product_id == item.crm_product_id)
      end
      next if po_item.nil?

      po_item.update_columns(received_qty: [po_item.received_qty.to_d - item.effective_qty, 0].max)
      next unless po.approved?

      po.reduce_on_order_for(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, qty: -item.effective_qty
      )
    end
    po.reload.recompute_receipt_status!
  end
end
