class Mes::PurchaseOrder < ApplicationRecord
  include Mes::DocumentNumber

  STATUSES = %w[DRAFT SUBMITTED PARTIAL_RECEIVED RECEIVED CANCELLED].freeze

  belongs_to :account
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :purchase_items, class_name: 'Mes::PurchaseItem', dependent: :destroy, inverse_of: :purchase_order
  accepts_nested_attributes_for :purchase_items, allow_destroy: true

  after_create :advance_production_order

  validates :po_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }

  def self.document_number_prefix = 'PU'
  def self.document_number_column = :po_no

  def recompute_total!
    update_column(:total_amount_micros, purchase_items.sum(:amount_micros))
  end

  private

  # 建采购单即把关联生产订单从「工程BOM」推进到「采购原料」。
  def advance_production_order
    return if production_order.nil?
    return unless production_order.stage == 'BOM_READY'

    production_order.update_columns(stage: 'PURCHASING', updated_at: Time.current)
  end
end
