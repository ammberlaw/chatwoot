# == Schema Information
#
# Table name: mes_production_orders
#
#  id                 :bigint           not null, primary key
#  actual_end_date    :datetime
#  actual_start_date  :datetime
#  delivery_date      :datetime
#  order_no           :string           not null
#  planned_end_date   :datetime
#  planned_start_date :datetime
#  produced_qty       :decimal(14, 3)   default(0.0), not null
#  product_name       :string           not null
#  qty                :decimal(14, 3)   not null
#  remark             :text
#  stage              :string           default("SALES_CONFIRMED"), not null
#  status             :string           default("IN_PROGRESS"), not null
#  unit               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  bom_id             :bigint
#  crm_product_id     :bigint
#  crm_sales_order_id :bigint
#  owner_id           :bigint
#
# Indexes
#
#  index_mes_production_orders_on_account_id               (account_id)
#  index_mes_production_orders_on_account_id_and_order_no  (account_id,order_no) UNIQUE
#  index_mes_production_orders_on_account_id_and_stage     (account_id,stage)
#  index_mes_production_orders_on_bom_id                   (bom_id)
#  index_mes_production_orders_on_crm_product_id           (crm_product_id)
#  index_mes_production_orders_on_crm_sales_order_id       (crm_sales_order_id)
#  index_mes_production_orders_on_owner_id                 (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_id => mes_boms.id) ON DELETE => nullify
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (crm_sales_order_id => crm_sales_orders.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Mes::ProductionOrder < ApplicationRecord
  include Mes::DocumentNumber

  # 8 阶段状态机（MES_SPEC §4）。顺序即推进顺序。
  STAGES = %w[
    SALES_CONFIRMED BOM_READY PURCHASING MATERIAL_INBOUND
    PICKING PRODUCTION FG_INBOUND SHIPPED
  ].freeze

  # 生命周期（与 stage 正交）。
  STATUSES = %w[IN_PROGRESS COMPLETED STOPPED CANCELLED].freeze

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :bom, class_name: 'Mes::Bom', optional: true
  belongs_to :owner, class_name: 'User', optional: true

  audited except: %i[created_at updated_at], on: %i[create update]
  has_many_attached :files

  after_create :mark_sales_order_in_production

  validates :product_name, presence: true
  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  validates :qty, presence: true, numericality: { greater_than: 0 }
  validates :stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where.not(status: 'CANCELLED') }

  def self.document_number_prefix = 'MO'

  # 进度 = 已产 / 计划产量（0..1）。
  def progress_ratio
    return 0 if qty.to_d.zero?

    (produced_qty.to_d / qty.to_d).clamp(0, 1)
  end

  # 挂工程 BOM（阶段 2）：绑 BOM、按预估交期天数算预估完工、进 BOM_READY。
  # planned_end 显式传入则优先；否则用 BOM 的 estimated_lead_days 从今天推算。
  def attach_bom!(bom, planned_end: nil)
    planned = planned_end.presence
    planned ||= bom.estimated_lead_days.present? ? bom.estimated_lead_days.to_i.days.from_now : nil
    updates = { bom_id: bom.id }
    updates[:planned_end_date] = planned if planned
    updates[:stage] = 'BOM_READY' if stage == 'SALES_CONFIRMED'
    update!(updates)
  end

  private

  # 转单即把来源销售订单推进为「生产中」（仅当还在待确认态，避免覆盖后续状态）。
  def mark_sales_order_in_production
    return if crm_sales_order.nil?
    return unless crm_sales_order.status == 'PENDING_CONFIRMATION'

    crm_sales_order.update_columns(status: 'IN_PRODUCTION', updated_at: Time.current)
  end
end
