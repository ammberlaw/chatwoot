# == Schema Information
#
# Table name: mes_shipments
#
#  id                  :bigint           not null, primary key
#  notified_at         :datetime
#  product_line        :string
#  remark              :text
#  shipment_no         :string           not null
#  shipped_at          :datetime
#  status              :string           default("DRAFT"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_customer_id     :bigint
#  crm_sales_order_id  :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#  warehouse_id        :bigint
#
# Indexes
#
#  index_mes_shipments_on_account_and_product_line    (account_id,product_line)
#  index_mes_shipments_on_account_id                  (account_id)
#  index_mes_shipments_on_account_id_and_shipment_no  (account_id,shipment_no) UNIQUE
#  index_mes_shipments_on_crm_customer_id             (crm_customer_id)
#  index_mes_shipments_on_crm_sales_order_id          (crm_sales_order_id)
#  index_mes_shipments_on_owner_id                    (owner_id)
#  index_mes_shipments_on_production_order_id         (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_sales_order_id => crm_sales_orders.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::Shipment < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  STATUSES = %w[DRAFT SHIPPED CANCELLED].freeze
  # 出库时销售订单可推进到 SHIPPED 的前置状态。
  SALES_ORDER_ADVANCEABLE = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT].freeze

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :shipment_items, class_name: 'Mes::ShipmentItem', dependent: :destroy, inverse_of: :shipment
  accepts_nested_attributes_for :shipment_items, allow_destroy: true
  has_many_attached :files

  validates :shipment_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  def self.document_number_prefix = 'DN'
  def self.document_number_column = :shipment_no

  # 通知出库（XMind 节点8）：仅打时间戳，供仓管/业务员据此备货。
  def notify!
    update!(notified_at: Time.current)
  end

  # 出库：开成品出库 StockEntry 扣成品库存（并把生产订单推进 SHIPPED），
  # 回写来源销售订单为「已出货」。
  def ship!
    raise StandardError, '单据已出库或已作废' unless status == 'DRAFT'

    transaction do
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
    end
    self
  end

  private

  def product_line_source = production_order

  def writeback_sales_order(timestamp)
    return if crm_sales_order.nil?
    return unless SALES_ORDER_ADVANCEABLE.include?(crm_sales_order.status)

    crm_sales_order.update_columns(status: 'SHIPPED', updated_at: timestamp)
  end
end
