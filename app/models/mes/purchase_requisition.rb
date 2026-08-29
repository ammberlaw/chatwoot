# == Schema Information
#
# Table name: mes_purchase_requisitions
#
#  id                  :bigint           not null, primary key
#  expected_date       :date
#  product_line        :string
#  purpose             :string           default("ORDER"), not null
#  remark              :text
#  req_no              :string           not null
#  status              :string           default("DRAFT"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  owner_id            :bigint
#  production_order_id :bigint
#
# Indexes
#
#  index_mes_purchase_requisitions_on_account_id             (account_id)
#  index_mes_purchase_requisitions_on_account_id_and_req_no  (account_id,req_no) UNIQUE
#  index_mes_purchase_requisitions_on_production_order_id    (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::PurchaseRequisition < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  # 采购申请单（请购）：工程/PMC 提需求 → 采购据此转采购单（可拆批、可改量、可备库存超量）。
  # 无审批闸：提交(OPEN)后采购即可见、可转单。
  PURPOSES = %w[ORDER STOCK ADHOC].freeze # 按单 / 备库存 / 临时
  STATUSES = %w[DRAFT OPEN PARTIAL_ORDERED ORDERED CANCELLED].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :requisition_items, class_name: 'Mes::PurchaseRequisitionItem', dependent: :destroy, inverse_of: :purchase_requisition
  has_many :purchase_orders, class_name: 'Mes::PurchaseOrder', dependent: :nullify
  accepts_nested_attributes_for :requisition_items, allow_destroy: true

  validates :req_no, presence: true, uniqueness: { scope: :account_id }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :status, inclusion: { in: STATUSES }

  scope :open_for_purchase, -> { where(status: %w[OPEN PARTIAL_ORDERED]) }

  def self.document_number_prefix = 'PR'
  def self.document_number_column = :req_no

  def draft? = status == 'DRAFT'
  def cancelled? = status == 'CANCELLED'

  # 转采购累加 ordered_qty 后重算单头状态：全部转齐=ORDERED、部分=PARTIAL_ORDERED、否则 OPEN。
  # DRAFT/CANCELLED 不动。
  def recompute_order_status!
    return if %w[DRAFT CANCELLED].include?(status)

    items = requisition_items.to_a
    new_status =
      if items.any? && items.all? { |i| i.ordered_qty.to_d >= i.suggested_qty.to_d }
        'ORDERED'
      elsif items.any? { |i| i.ordered_qty.to_d.positive? }
        'PARTIAL_ORDERED'
      else
        'OPEN'
      end
    update_column(:status, new_status) if new_status != status
  end

  private

  # 按单请购随生产订单产品线；备库存/临时无来源单，回退控制器兜底当前产线。
  def product_line_source = production_order
end
