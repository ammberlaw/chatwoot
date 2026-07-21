# 成品序列号（务实版追溯：SN ← 工单 ← BOM/物料；SN → 客户/出库，接售后 RMA）。
class Mes::SerialNumber < ApplicationRecord
  STATUSES = %w[IN_STOCK SHIPPED RMA].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :shipment, class_name: 'Mes::Shipment', optional: true

  validates :sn, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
end
