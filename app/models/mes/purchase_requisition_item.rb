# == Schema Information
#
# Table name: mes_purchase_requisition_items
#
#  id                      :bigint           not null, primary key
#  item_type               :string           default("MATERIAL"), not null
#  material_name           :string
#  material_no             :string
#  ordered_qty             :decimal(14, 3)   default(0.0), not null
#  remark                  :text
#  required_qty            :decimal(14, 3)   default(0.0), not null
#  specification           :string
#  suggested_qty           :decimal(14, 3)   default(0.0), not null
#  unit                    :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  crm_product_id          :bigint
#  mes_material_id         :bigint
#  mes_supplier_id         :bigint
#  purchase_requisition_id :bigint           not null
#
# Indexes
#
#  idx_mes_pr_items_on_pr_id                           (purchase_requisition_id)
#  index_mes_purchase_requisition_items_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (mes_supplier_id => mes_suppliers.id) ON DELETE => nullify
#  fk_rails_...  (purchase_requisition_id => mes_purchase_requisitions.id) ON DELETE => cascade
#
class Mes::PurchaseRequisitionItem < ApplicationRecord
  # MATERIAL=生产用料（挂 mes_material）；PRODUCT=外购成品（挂 crm_product）。与采购单明细同口径。
  ITEM_TYPES = %w[MATERIAL PRODUCT].freeze

  belongs_to :account
  belongs_to :purchase_requisition, class_name: 'Mes::PurchaseRequisition', inverse_of: :requisition_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true

  before_validation :inherit_account

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :material_name, presence: true
  validates :suggested_qty, numericality: { greater_than: 0 }

  # 剩余可转采购量 = 建议采购量 − 已转采购量（拆批转单时预填本批量）。
  def remaining_qty
    [suggested_qty.to_d - ordered_qty.to_d, 0].max
  end

  private

  def inherit_account
    self.account_id ||= purchase_requisition&.account_id
  end
end
