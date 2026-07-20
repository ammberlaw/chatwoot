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
