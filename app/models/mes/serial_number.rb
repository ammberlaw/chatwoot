# 成品序列号（务实版追溯：SN ← 工单 ← BOM/物料；SN → 客户/出库，接售后 RMA）。
# == Schema Information
#
# Table name: mes_serial_numbers
#
#  id                  :bigint           not null, primary key
#  product_line        :string
#  remark              :text
#  sn                  :string           not null
#  status              :string           default("IN_STOCK"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_product_id      :bigint
#  production_order_id :bigint
#  shipment_id         :bigint
#
# Indexes
#
#  index_mes_serial_numbers_on_account_and_product_line  (account_id,product_line)
#  index_mes_serial_numbers_on_account_id                (account_id)
#  index_mes_serial_numbers_on_account_id_and_sn         (account_id,sn) UNIQUE
#  index_mes_serial_numbers_on_crm_product_id            (crm_product_id)
#  index_mes_serial_numbers_on_production_order_id       (production_order_id)
#  index_mes_serial_numbers_on_shipment_id               (shipment_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (shipment_id => mes_shipments.id) ON DELETE => nullify
#
class Mes::SerialNumber < ApplicationRecord
  include Mes::LineScoped

  STATUSES = %w[IN_STOCK SHIPPED RMA].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :shipment, class_name: 'Mes::Shipment', optional: true

  validates :sn, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  private

  def product_line_source = production_order || crm_product
end
