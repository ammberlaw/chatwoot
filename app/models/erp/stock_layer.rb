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
#  crm_product_id   :bigint           not null
#  source_id        :bigint
#  warehouse_id     :bigint           not null
#
# Indexes
#
#  idx_erp_stock_layers_fifo                            (account_id,crm_product_id,warehouse_id,received_at)
#  index_erp_stock_layers_on_account_id                 (account_id)
#  index_erp_stock_layers_on_source_type_and_source_id  (source_type,source_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => restrict
#  fk_rails_...  (warehouse_id => mes_warehouses.id) ON DELETE => restrict
#
class Erp::StockLayer < ApplicationRecord
  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product'
  belongs_to :warehouse, class_name: 'Mes::Warehouse'
  has_many :consumptions, class_name: 'Erp::StockConsumption',
                          dependent: :restrict_with_error, inverse_of: :stock_layer

  validates :qty_in, :qty_remaining, numericality: { greater_than_or_equal_to: 0 }
  validates :unit_cost_micros, numericality: { greater_than_or_equal_to: 0 }

  # 还有余量的层，按入库时间排——FIFO 的「先进」就是这个顺序。
  # 同一时刻入库的按 id 兜底，保证取层顺序稳定可复现。
  scope :open_layers, -> { where('qty_remaining > 0').order(:received_at, :id) }
  scope :for_item, lambda { |product_id, warehouse_id|
    where(crm_product_id: product_id, warehouse_id: warehouse_id)
  }

  def amount_remaining_micros
    (qty_remaining * unit_cost_micros).round
  end
end
