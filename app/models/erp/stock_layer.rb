# 成品存货批次层（FIFO 一层 = 一次入库）。出库按 received_at 从早到晚逐层扣。
#
# 为什么是层不是一个平均价：金蝶用先进先出，平行跑账要对得上就得保留每批的原始单价，
# 出库时按进货顺序消耗。移动加权只需维护一对「数量+金额」，但那是另一种算法，数字对不上。
# == Schema Information
#
# Table name: erp_stock_layers
#
#  id               :bigint           not null, primary key
#  qty_in           :decimal(16, 3)   not null
#  qty_remaining    :decimal(16, 3)   not null
#  received_at      :datetime         not null
#  remark           :text
#  source_type      :string           not null
#  unit_cost_micros :bigint           default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  crm_product_id   :bigint
#  mes_material_id  :bigint
#  source_id        :bigint
#  warehouse_id     :bigint           not null
#
# Indexes
#
#  idx_erp_stock_layers_fifo                            (account_id,crm_product_id,warehouse_id,received_at)
#  index_erp_stock_layers_on_account_id                 (account_id)
#  index_erp_stock_layers_on_material_and_wh            (account_id,mes_material_id,warehouse_id)
#  index_erp_stock_layers_on_source_type_and_source_id  (source_type,source_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => restrict
#  fk_rails_...  (warehouse_id => mes_warehouses.id) ON DELETE => restrict
#
class Erp::StockLayer < ApplicationRecord
  belongs_to :account
  # 成品层挂商品档，原料层多数挂物料档——同一颗料在不同单据上挂法不一，两种都认。
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse'
  has_many :consumptions, class_name: 'Erp::StockConsumption',
                          dependent: :restrict_with_error, inverse_of: :stock_layer

  validates :qty_in, :qty_remaining, numericality: { greater_than_or_equal_to: 0 }
  validates :unit_cost_micros, numericality: { greater_than_or_equal_to: 0 }

  # 还有余量的层，按入库时间排——FIFO 的「先进」就是这个顺序。
  # 同一时刻入库的按 id 兜底，保证取层顺序稳定可复现。
  scope :open_layers, -> { where('qty_remaining > 0').order(:received_at, :id) }
  # 取层的归一入口：优先按物料档对，没有物料 id 才按商品档对。
  # 一颗料只能走一条——两边都匹配会把同一批货取两遍。
  scope :for_item, lambda { |product_id, warehouse_id, material_id = nil|
    base = where(warehouse_id: warehouse_id)
    material_id.present? ? base.where(mes_material_id: material_id) : base.where(crm_product_id: product_id)
  }

  validate :item_present

  def amount_remaining_micros
    (qty_remaining * unit_cost_micros).round
  end

  private

  def item_present
    return if crm_product_id.present? || mes_material_id.present?

    errors.add(:base, '批次层必须挂商品档或物料档')
  end
end
