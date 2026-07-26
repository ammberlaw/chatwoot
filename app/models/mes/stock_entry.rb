# == Schema Information
#
# Table name: mes_stock_entries
#
#  id                  :bigint           not null, primary key
#  actual_inbound_date :datetime
#  color               :string
#  entry_no            :string           not null
#  is_checked          :boolean          default(FALSE), not null
#  posted_at           :datetime
#  product_line        :string
#  purpose             :string           not null
#  remark              :text
#  status              :string           default("DRAFT"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  checked_by_id       :bigint
#  from_warehouse_id   :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#  purchase_order_id   :bigint
#  received_by_id      :bigint
#  to_warehouse_id     :bigint
#
# Indexes
#
#  index_mes_stock_entries_on_account_and_product_line  (account_id,product_line)
#  index_mes_stock_entries_on_account_id                (account_id)
#  index_mes_stock_entries_on_account_id_and_entry_no   (account_id,entry_no) UNIQUE
#  index_mes_stock_entries_on_account_id_and_purpose    (account_id,purpose)
#  index_mes_stock_entries_on_owner_id                  (owner_id)
#  index_mes_stock_entries_on_production_order_id       (production_order_id)
#  index_mes_stock_entries_on_purchase_order_id         (purchase_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => nullify
#
class Mes::StockEntry < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

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
  has_many :stock_entry_items, class_name: 'Mes::StockEntryItem', dependent: :destroy, inverse_of: :stock_entry
  accepts_nested_attributes_for :stock_entry_items, allow_destroy: true

  validates :entry_no, presence: true, uniqueness: { scope: :account_id }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :status, inclusion: { in: STATUSES }

  scope :posted, -> { where(status: 'POSTED') }

  def self.document_number_prefix = 'SE'
  def self.document_number_column = :entry_no

  # 过账：按 purpose 方向对每个明细刷结存、记流水，然后置 POSTED。
  # 原料入库过账把关联生产订单推进到「原料入库」阶段。
  def post!
    raise StandardError, '单据已过账或已作废' unless status == 'DRAFT'

    transaction do
      ts = Time.current
      stock_entry_items.each { |item| post_item(item, ts) }
      update_columns(status: 'POSTED', posted_at: ts, updated_at: ts)
      advance_production_order_on_receipt(ts)
    end
    self
  end

  private

  def product_line_source = production_order || purchase_order

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
    return if production_order.stage != from_stage

    production_order.enter_stage!(to_stage, at: timestamp)
  end
end
