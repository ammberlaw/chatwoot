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
#  stage_ack_at       :datetime
#  status             :string           default("IN_PROGRESS"), not null
#  unit               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  bom_id             :bigint
#  crm_product_id     :bigint
#  crm_sales_order_id :bigint
#  owner_id           :bigint
#  stage_ack_by_id    :bigint
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
#  index_mes_production_orders_on_stage_ack_by_id           (stage_ack_by_id)
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

  # 每个阶段对应的前端板块（board_key），用于查该阶段负责人（Mes::BoardOwner）。SHIPPED 为终点无需接单。
  STAGE_BOARD_KEYS = {
    'SALES_CONFIRMED' => 'mes_production_orders_index',
    'BOM_READY' => 'mes_boms_index',
    'PURCHASING' => 'mes_purchase_orders_index',
    'MATERIAL_INBOUND' => 'mes_stock_entries_index',
    'PICKING' => 'mes_material_issues_index',
    'PRODUCTION' => 'mes_production_records_index',
    'FG_INBOUND' => 'mes_fg_inbound_index'
  }.freeze

  # 接单时限：进入阶段后 N 小时内负责人须接单，超时即「未接单超时」并可升级。
  ACK_LIMIT_HOURS = 4

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :bom, class_name: 'Mes::Bom', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :stage_ack_by, class_name: 'User', optional: true
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
  # 换阶段即清空接单状态——新一次交接须重新接单，计时以本次 entered_at 为准。
  def enter_stage!(new_stage, at: nil, actor: nil)
    at ||= Time.current
    unless stage == new_stage
      update_columns(stage: new_stage, stage_ack_at: nil, stage_ack_by_id: nil, updated_at: at)
    end
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
    lead = bom.total_lead_days
    planned ||= lead.positive? ? lead.days.from_now : nil
    updates = { bom_id: bom.id }
    updates[:planned_end_date] = planned if planned
    update!(updates)
    enter_stage!('BOM_READY') if stage == 'SALES_CONFIRMED'
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING），通知采购备料。
  def release_to_purchasing!(actor: nil)
    raise StandardError, '需先挂工程/PMC BOM' if bom_id.nil?
    raise StandardError, '当前阶段无法下发采购' unless stage == 'BOM_READY'

    enter_stage!('PURCHASING', actor: actor)
    self
  end

  # 报工累加已产数量；首次报工把阶段从「生产领料」推进到「生产」。
  def add_produced!(delta)
    update_columns(produced_qty: produced_qty.to_d + delta.to_d, updated_at: Time.current)
    enter_stage!('PRODUCTION') if stage == 'PICKING'
  end

  # BOM 算料（XMind 节点3）：按 BOM 用量 × 本单产量/基准产量，展开采购需求。
  # 返回 [{ mes_material_id, material_no, material_name, specification, unit, qty }]，供采购单预填。
  def material_requirements
    return [] if bom.nil? || bom.base_qty.to_d.zero?

    factor = qty.to_d / bom.base_qty.to_d
    bom.bom_items.map do |item|
      {
        mes_material_id: item.mes_material_id,
        material_no: item.material_no,
        material_name: item.material_name,
        specification: item.specification,
        unit: item.unit,
        qty: (item.qty.to_d * factor)
      }
    end
  end

  # ── 接单确认（P1）：接单只是「表态」，不阻塞流程；计时始终以进入阶段时间为准 ──

  # 当前阶段的到达时间（本阶段最近一次进入）。
  def stage_entered_at
    stage_events.select { |e| e.stage == stage }.map(&:entered_at).compact.max
  end

  # 本阶段需要接单吗？终点（SHIPPED，无 board_key）与非进行中订单不需要。
  def ack_required?
    status == 'IN_PROGRESS' && STAGE_BOARD_KEYS.key?(stage)
  end

  def awaiting_ack?
    ack_required? && stage_ack_at.nil?
  end

  # 接单截止 = 进入阶段 + 接单时限。
  def ack_deadline
    entered = stage_entered_at
    entered && (entered + ACK_LIMIT_HOURS.hours)
  end

  # 未接单超时（装死）：到点还没接单。用于点名 + 升级，不看是否配了负责人。
  def ack_overdue?
    awaiting_ack? && ack_deadline.present? && ack_deadline < Time.current
  end

  # 当前阶段负责人的 user_id（取该阶段板块负责人）。
  def current_stage_owner_ids
    key = STAGE_BOARD_KEYS[stage]
    return [] unless key

    account.mes_board_owners.find_by(board_key: key)&.manager_ids || []
  end

  # 接单：标记谁在何时接手（update! 触发审计留痕）。
  def acknowledge!(actor)
    raise StandardError, '当前阶段无需接单' unless awaiting_ack?

    update!(stage_ack_at: Time.current, stage_ack_by_id: actor&.id)
    self
  end

  # 拒收打回：退回上一阶段并记原因；上一阶段重新计时、需重新接单，责任明确回上游。
  def reject_to_previous!(actor:, reason:)
    idx = STAGES.index(stage)
    raise StandardError, '已是初始阶段，无法退回' if idx.nil? || idx.zero?

    prev = STAGES[idx - 1]
    now = Time.current
    transaction do
      update_columns(stage: prev, stage_ack_at: nil, stage_ack_by_id: nil, updated_at: now)
      ev = stage_events.find_or_create_by!(stage: prev) { |e| e.account_id = account_id }
      ev.update!(entered_at: now, actor_id: actor&.id, note: "被下游退回：#{reason}")
    end
    self
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
