# 出库消耗记录：某张出库单从某个批次层扣了多少、按什么单价。
#
# 存在的理由是作废：出库单作废要把货还回原来那几层。如果不记，只能按 FIFO 重算一遍，
# 但中间若又进过货，重算出来的层跟当初消耗的根本不是同一批，还回去就错了。
# == Schema Information
#
# Table name: erp_stock_consumptions
#
#  id                 :bigint           not null, primary key
#  base_amount_micros :bigint           not null
#  qty                :decimal(16, 3)   not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_product_id     :bigint           not null
#  mes_stock_entry_id :bigint           not null
#  stock_layer_id     :bigint           not null
#
# Indexes
#
#  idx_erp_stock_consumptions_entry                (account_id,mes_stock_entry_id)
#  index_erp_stock_consumptions_on_account_id      (account_id)
#  index_erp_stock_consumptions_on_stock_layer_id  (stock_layer_id)
#
# Foreign Keys
#
#  fk_rails_...  (mes_stock_entry_id => mes_stock_entries.id) ON DELETE => cascade
#  fk_rails_...  (stock_layer_id => erp_stock_layers.id) ON DELETE => restrict
#
class Erp::StockConsumption < ApplicationRecord
  belongs_to :account
  belongs_to :stock_layer, class_name: 'Erp::StockLayer', inverse_of: :consumptions
  belongs_to :stock_entry, class_name: 'Mes::StockEntry', foreign_key: :mes_stock_entry_id, inverse_of: false
  belongs_to :crm_product, class_name: 'Crm::Product'

  validates :qty, numericality: { greater_than: 0 }
end
