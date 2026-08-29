# == Schema Information
#
# Table name: mes_stock_entries
#
#  id                        :bigint           not null, primary key
#  actual_inbound_date       :datetime
#  color                     :string
#  entry_no                  :string           not null
#  is_checked                :boolean          default(FALSE), not null
#  posted_at                 :datetime
#  product_line              :string
#  purpose                   :string           not null
#  remark                    :text
#  status                    :string           default("DRAFT"), not null
#  warehouse_confirmed_at    :datetime
#  workshop_confirmed_at     :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
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
#  index_mes_stock_entries_on_account_and_product_line   (account_id,product_line)
#  index_mes_stock_entries_on_account_id                 (account_id)
#  index_mes_stock_entries_on_account_id_and_entry_no    (account_id,entry_no) UNIQUE
#  index_mes_stock_entries_on_account_id_and_purpose     (account_id,purpose)
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
  PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_ISSUE MATERIAL_RETURN MANUFACTURE SCRAP SHIPMENT].freeze
  IN_PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_RETURN MANUFACTURE].freeze
  STATUSES = %w[DRAFT POSTED CANCELLED].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :checked_by, class_name: 'User', optional: true
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

  before_create :stamp_workshop_confirm
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
    raise StandardError, '单据已过账或已作废' unless status == 'DRAFT'
    raise StandardError, '成品入库需车间负责人与仓管共同确认后方可过账' if dual_confirm_required? && !dual_confirmed?

    transaction do
      ts = Time.current
      stock_entry_items.each { |item| post_item(item, ts) }
      update_columns(status: 'POSTED', posted_at: ts, updated_at: ts)
      sync_purchase_receipt! if purpose == 'MATERIAL_RECEIPT' && purchase_order_id.present?
      advance_production_order_on_receipt(ts)
    end
    self
  end

  private

  def product_line_source = production_order || purchase_order

  # 车间开单即视为车间确认（开单人盖章）。
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
    warehouse_id = item.warehouse_id || default_warehouse_id
    raise StandardError, "明细缺仓库（#{item.item_type}）" if warehouse_id.nil?

    delta = direction_sign * item.effective_qty
    balance_after = Mes::StockBalance.apply!(
      account_id: account_id, item_type: item.item_type, warehouse_id: warehouse_id,
      mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id, delta: delta
    )
    account.mes_stock_ledgers.create!(
      item_type: item.item_type, mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id,
      warehouse_id: warehouse_id, stock_entry_id: id, qty_change: delta, balance_after: balance_after, posted_at: timestamp
    )
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

  # 原料入库过账：按物料把本次收货量累加回采购单明细 received_qty、回填实际到料日期，并重算收货状态。
  # 修复历史遗留（received_qty 从不回写，导致「按采购单收货」剩余量预填失效）+ 支撑齐套判定。
  # 实际到料 = 本次入库日期（首次到料自动填，分批到料覆盖为最近一次；采购员仍可在采购单上手动改）。
  # 本次到料日期：入库单填了实际入库日就用它，否则用过账当下。
  def receipt_arrival_at = actual_inbound_date || Time.current

  def sync_purchase_receipt!
    po = purchase_order
    arrival = receipt_arrival_at
    stock_entry_items.each do |item|
      po_item = po.purchase_items.find do |pi|
        (item.mes_material_id && pi.mes_material_id == item.mes_material_id) ||
          (item.crm_product_id && pi.crm_product_id == item.crm_product_id)
      end
      next if po_item.nil?

      po_item.update_columns(
        received_qty: po_item.received_qty.to_d + item.effective_qty,
        arrival_date: arrival
      )
      # 到货冲减采购单在途（已订购未到货）量——收多少冲多少（仅审批通过、累加过在途的单）。
      if po.approved?
        po.reduce_on_order_for(
          item_type: item.item_type, mes_material_id: item.mes_material_id,
          crm_product_id: item.crm_product_id, qty: item.effective_qty
        )
      end
    end
    po.reload.recompute_receipt_status!
  end
end
