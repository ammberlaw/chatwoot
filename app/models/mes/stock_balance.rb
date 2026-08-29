# == Schema Information
#
# Table name: mes_stock_balances
#
#  id              :bigint           not null, primary key
#  item_type       :string           not null
#  on_order_qty    :decimal(16, 3)   default(0.0), not null
#  product_line    :string
#  qty             :decimal(16, 3)   default(0.0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_product_id  :bigint
#  mes_material_id :bigint
#  warehouse_id    :bigint           not null
#
# Indexes
#
#  index_mes_stock_balances_on_account_and_product_line  (account_id,product_line)
#  index_mes_stock_balances_on_account_id                (account_id)
#  index_mes_stock_balances_on_crm_product_id            (crm_product_id)
#  index_mes_stock_balances_on_mes_material_id           (mes_material_id)
#  index_mes_stock_balances_unique                       (account_id,item_type,mes_material_id,crm_product_id,warehouse_id) UNIQUE NULLS NOT DISTINCT
#
class Mes::StockBalance < ApplicationRecord
  include Mes::LineScoped

  belongs_to :account
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse', optional: true

  # 低于安全库存（仅物料有安全库存阈值）。
  def short?
    ss = mes_material&.safety_stock
    ss.present? && ss.positive? && qty < ss
  end

  # 对某物料/成品 × 仓库的结存施加增量，返回过账后结存（原子递增）。
  def self.apply!(account_id:, item_type:, warehouse_id:, delta:, mes_material_id: nil, crm_product_id: nil)
    row = find_or_create_by!(
      account_id: account_id, item_type: item_type, warehouse_id: warehouse_id,
      mes_material_id: mes_material_id, crm_product_id: crm_product_id
    )
    row.with_lock do
      row.update!(qty: row.qty + delta)
    end
    row.qty
  end

  # 对某物料/成品 × 仓库的在途量（已订购未到货）施加增量，floor 0（原子递增）。
  # 采购审批通过 +delta、到货冲减 -delta。
  def self.apply_on_order!(account_id:, item_type:, warehouse_id:, delta:, mes_material_id: nil, crm_product_id: nil)
    row = find_or_create_by!(
      account_id: account_id, item_type: item_type, warehouse_id: warehouse_id,
      mes_material_id: mes_material_id, crm_product_id: crm_product_id
    )
    row.with_lock do
      row.update!(on_order_qty: [row.on_order_qty + delta, 0].max)
    end
    row.on_order_qty
  end

  private

  def product_line_source = mes_material || crm_product
end
