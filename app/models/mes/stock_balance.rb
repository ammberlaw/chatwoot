class Mes::StockBalance < ApplicationRecord
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
end
