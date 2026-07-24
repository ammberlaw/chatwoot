# == Schema Information
#
# Table name: mes_purchase_orders
#
#  id                  :bigint           not null, primary key
#  arrival_date        :datetime
#  exception_note      :text
#  expected_date       :datetime
#  follow_up_date      :datetime
#  has_exception       :boolean          default(FALSE), not null
#  po_no               :string           not null
#  product_line        :string
#  remark              :text
#  status              :string           default("DRAFT"), not null
#  total_amount_micros :bigint
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  mes_supplier_id     :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#
# Indexes
#
#  index_mes_purchase_orders_on_account_and_product_line  (account_id,product_line)
#  index_mes_purchase_orders_on_account_id                (account_id)
#  index_mes_purchase_orders_on_account_id_and_po_no      (account_id,po_no) UNIQUE
#  index_mes_purchase_orders_on_account_id_and_status     (account_id,status)
#  index_mes_purchase_orders_on_mes_supplier_id           (mes_supplier_id)
#  index_mes_purchase_orders_on_owner_id                  (owner_id)
#  index_mes_purchase_orders_on_production_order_id       (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (mes_supplier_id => mes_suppliers.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::PurchaseOrder < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

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

  def product_line_source = production_order

  # 建采购单即把关联生产订单从「工程BOM」推进到「采购原料」。
  def advance_production_order
    return if production_order.nil?
    return unless production_order.stage == 'BOM_READY'

    production_order.enter_stage!('PURCHASING', at: Time.current)
  end
end
