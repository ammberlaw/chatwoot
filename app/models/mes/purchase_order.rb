# == Schema Information
#
# Table name: mes_purchase_orders
#
#  id                  :bigint           not null, primary key
#  delivery_date       :date
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
#  owner_id            :bigint
#  production_order_id :bigint
#
# Indexes
#
#  index_mes_purchase_orders_on_account_and_product_line  (account_id,product_line)
#  index_mes_purchase_orders_on_account_id                (account_id)
#  index_mes_purchase_orders_on_account_id_and_po_no      (account_id,po_no) UNIQUE
#  index_mes_purchase_orders_on_account_id_and_status     (account_id,status)
#  index_mes_purchase_orders_on_owner_id                  (owner_id)
#  index_mes_purchase_orders_on_production_order_id       (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::PurchaseOrder < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  include Mes::Returnable

  STATUSES = %w[DRAFT SUBMITTED PARTIAL_RECEIVED RECEIVED CANCELLED].freeze

  belongs_to :account
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

  # 收货齐套状态：按明细 received_qty 与订购量派生——全部收齐=RECEIVED、部分=PARTIAL_RECEIVED。
  # 收货由挂本单的原料入库单过账驱动（见 Mes::StockEntry#sync_purchase_receipt!），非手工改。
  # 支撑生产订单齐套判定（一单多采购单时，所有采购单都 RECEIVED 才推进到原料入库）。
  def recompute_receipt_status!
    return if status == 'CANCELLED'

    items = purchase_items.to_a
    return if items.empty?

    new_status =
      if items.all? { |i| i.received_qty.to_d >= i.qty.to_d }
        'RECEIVED'
      elsif items.any? { |i| i.received_qty.to_d.positive? }
        'PARTIAL_RECEIVED'
      else
        status
      end
    update_column(:status, new_status) if new_status != status
  end

  def received? = status == 'RECEIVED'

  # ── 单据退回（Mes::Returnable）──：退回目标 = 工程/PMC BOM 板块。
  def document_board_key = 'mes_purchase_orders_index'
  def return_document_label = '采购单'
  def return_document_no = po_no
  # 已全部收货 / 已作废的采购单不可退回。
  def returnable? = %w[DRAFT SUBMITTED PARTIAL_RECEIVED].include?(status)

  private

  def product_line_source = production_order

  # 建采购单即把关联生产订单从「工程BOM」推进到「采购原料」。
  def advance_production_order
    return if production_order.nil?
    return unless production_order.stage == 'BOM_READY'

    production_order.enter_stage!('PURCHASING', at: Time.current)
  end
end
