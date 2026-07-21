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
#  product_line       :string
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
#  index_mes_production_orders_on_account_and_product_line  (account_id,product_line)
#  index_mes_production_orders_on_account_id                (account_id)
#  index_mes_production_orders_on_account_id_and_order_no   (account_id,order_no) UNIQUE
#  index_mes_production_orders_on_account_id_and_stage      (account_id,stage)
#  index_mes_production_orders_on_bom_id                    (bom_id)
#  index_mes_production_orders_on_crm_product_id            (crm_product_id)
#  index_mes_production_orders_on_crm_sales_order_id        (crm_sales_order_id)
#  index_mes_production_orders_on_owner_id                  (owner_id)
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
  include Mes::LineScoped

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
  has_many :stage_events, class_name: 'Mes::ProductionOrderStageEvent', dependent: :destroy, inverse_of: :production_order

  audited except: %i[created_at updated_at], on: %i[create update]
  has_many_attached :files

  after_create :mark_sales_order_in_production
  after_create :record_initial_stage

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

  # 统一阶段推进：置 stage 并记一条到达事件（同阶段已记则跳过，幂等）。
  def enter_stage!(new_stage, at: nil, actor: nil)
    at ||= Time.current
    update_columns(stage: new_stage, updated_at: at) unless stage == new_stage
    stage_events.find_or_create_by!(stage: new_stage) do |e|
      e.account_id = account_id
      e.entered_at = at
      e.actor_id = actor&.id
    end
  end

  # 挂工程 BOM（阶段 2）：绑 BOM、按预估交期天数算预估完工、进 BOM_READY。
  # planned_end 显式传入则优先；否则用 BOM 的 estimated_lead_days 从今天推算。
  def attach_bom!(bom, planned_end: nil)
    planned = planned_end.presence
    planned ||= bom.estimated_lead_days.present? ? bom.estimated_lead_days.to_i.days.from_now : nil
    updates = { bom_id: bom.id }
    updates[:planned_end_date] = planned if planned
    update!(updates)
    enter_stage!('BOM_READY') if stage == 'SALES_CONFIRMED'
  end

  # 实际耗料成本（已过账领料 - 退料，× 物料标准价）。
  def actual_material_cost_micros
    entries = account.mes_stock_entries
                     .where(production_order_id: id, status: 'POSTED', purpose: %w[MATERIAL_ISSUE MATERIAL_RETURN])
                     .includes(stock_entry_items: :mes_material)
    entries.sum do |entry|
      sign = entry.purpose == 'MATERIAL_ISSUE' ? 1 : -1
      entry.stock_entry_items.sum { |item| sign * item.effective_qty * (item.mes_material&.cost_price_micros || 0) }
    end.round
  end

  # 计划耗料成本（BOM 汇总 × 本单产量/基准产量）。
  def planned_material_cost_micros
    return nil if bom.nil? || bom.base_qty.to_d.zero?

    (bom.total_material_cost_micros.to_i * (qty.to_d / bom.base_qty.to_d)).round
  end

  def unit_material_cost_micros
    base = produced_qty.to_d.positive? ? produced_qty.to_d : qty.to_d
    return nil if base.zero?

    (actual_material_cost_micros / base).round
  end

  def sales_amount_micros = crm_sales_order&.order_amount_micros

  # 毛利（销售额 - 实际耗料，物料口径；人工/制费后期）。
  def gross_margin_micros
    return nil if sales_amount_micros.nil?

    sales_amount_micros - actual_material_cost_micros
  end

  # 报工累加已产数量；首次报工把阶段从「生产领料」推进到「生产」。
  def add_produced!(delta)
    update_columns(produced_qty: produced_qty.to_d + delta.to_d, updated_at: Time.current)
    enter_stage!('PRODUCTION') if stage == 'PICKING'
  end

  # BOM 算料（XMind 节点3）：按 BOM 用量 × 本单产量/基准产量，展开采购需求。
  # 返回 [{ mes_material_id, material_name, unit, qty, rate_micros }]，供采购单预填。
  def material_requirements
    return [] if bom.nil? || bom.base_qty.to_d.zero?

    factor = qty.to_d / bom.base_qty.to_d
    bom.bom_items.includes(:mes_material).map do |item|
      material = item.mes_material
      {
        mes_material_id: item.mes_material_id,
        material_name: material&.name,
        unit: item.unit.presence || material&.unit,
        qty: (item.qty.to_d * factor),
        rate_micros: item.rate_micros
      }
    end
  end

  private

  def product_line_source = crm_product

  # 建单即记初始阶段（销售订单确定）到达时间。
  def record_initial_stage
    stage_events.create!(account_id: account_id, stage: stage, entered_at: created_at || Time.current)
  end

  # 转单即把来源销售订单推进为「生产中」（仅当还在待确认态，避免覆盖后续状态）。
  def mark_sales_order_in_production
    return if crm_sales_order.nil?
    return unless crm_sales_order.status == 'PENDING_CONFIRMATION'

    crm_sales_order.update_columns(status: 'IN_PRODUCTION', updated_at: Time.current)
  end
end
