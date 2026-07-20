# == Schema Information
#
# Table name: mes_boms
#
#  id                         :bigint           not null, primary key
#  base_qty                   :decimal(14, 3)   default(1.0), not null
#  bom_no                     :string           not null
#  estimated_lead_days        :integer
#  is_active                  :boolean          default(TRUE), not null
#  is_default                 :boolean          default(FALSE), not null
#  remark                     :text
#  total_material_cost_micros :bigint
#  unit                       :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  crm_product_id             :bigint
#  owner_id                   :bigint
#
# Indexes
#
#  index_mes_boms_on_account_id             (account_id)
#  index_mes_boms_on_account_id_and_bom_no  (account_id,bom_no) UNIQUE
#  index_mes_boms_on_crm_product_id         (crm_product_id)
#  index_mes_boms_on_owner_id               (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Mes::Bom < ApplicationRecord
  include Mes::DocumentNumber

  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :bom_items, class_name: 'Mes::BomItem', dependent: :destroy, inverse_of: :bom
  accepts_nested_attributes_for :bom_items, allow_destroy: true

  validates :bom_no, presence: true, uniqueness: { scope: :account_id }
  validates :base_qty, numericality: { greater_than: 0 }

  scope :active, -> { where(is_active: true) }

  def self.document_number_prefix = 'BOM'
  def self.document_number_column = :bom_no

  # 用料汇总成本（只读，随明细增改回写）。
  def recompute_total_cost!
    update_column(:total_material_cost_micros, bom_items.sum(:amount_micros))
  end
end
