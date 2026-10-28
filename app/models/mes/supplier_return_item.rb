# 退料返修单的明细行：退了哪颗料、退多少、回来多少。
# == Schema Information
#
# Table name: mes_supplier_return_items
#
#  id                 :bigint           not null, primary key
#  qty                :decimal(14, 3)   default(0.0), not null
#  remark             :text
#  returned_qty       :decimal(14, 3)   default(0.0), not null
#  unit               :string
#  unit_price_micros  :bigint           default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_product_id     :bigint
#  supplier_return_id :bigint           not null
#
# Indexes
#
#  index_mes_supplier_return_items_on_crm_product_id      (crm_product_id)
#  index_mes_supplier_return_items_on_supplier_return_id  (supplier_return_id)
#
class Mes::SupplierReturnItem < ApplicationRecord
  belongs_to :account
  belongs_to :supplier_return, class_name: 'Mes::SupplierReturn', inverse_of: :items
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true

  validates :qty, numericality: { greater_than: 0 }

  # 还没回来的数量（负数没意义，夹到 0）。
  def outstanding_qty = [qty.to_d - returned_qty.to_d, 0].max
end
