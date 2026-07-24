# == Schema Information
#
# Table name: mes_production_orders
#
#  id                  :bigint           not null, primary key
#  actual_end_date     :datetime
#  actual_start_date   :datetime
#  approval_status     :string           default("DRAFT"), not null
#  bom_confirmed_at    :datetime
#  delivery_date       :datetime
#  gm_acted_at         :datetime
#  gm_comment          :text
#  is_draft            :boolean          default(FALSE), not null
#  manager_acted_at    :datetime
#  manager_comment     :text
#  order_no            :string           not null
#  pi_no               :string
#  planned_end_date    :datetime
#  planned_start_date  :datetime
#  produced_qty        :decimal(14, 3)   default(0.0), not null
#  product_code        :string
#  product_line        :string
#  product_name        :string           not null
#  qty                 :decimal(14, 3)   not null
#  remark              :text
#  spec                :jsonb            not null
#  stage               :string           default("SALES_CONFIRMED"), not null
#  stage_ack_at        :datetime
#  status              :string           default("IN_PROGRESS"), not null
#  submitted_at        :datetime
#  unit                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  bom_confirmed_by_id :bigint
#  bom_id              :bigint
#  crm_product_id      :bigint
#  crm_sales_order_id  :bigint
#  gm_id               :bigint
#  manager_id          :bigint
#  owner_id            :bigint
#  stage_ack_by_id     :bigint
#
# Indexes
#
#  index_mes_production_orders_on_account_and_product_code        (account_id,product_code)
#  index_mes_production_orders_on_account_and_product_line        (account_id,product_line)
#  index_mes_production_orders_on_account_id                      (account_id)
#  index_mes_production_orders_on_account_id_and_approval_status  (account_id,approval_status)
#  index_mes_production_orders_on_account_id_and_is_draft         (account_id,is_draft)
#  index_mes_production_orders_on_account_id_and_order_no         (account_id,order_no) UNIQUE
#  index_mes_production_orders_on_account_id_and_stage            (account_id,stage)
#  index_mes_production_orders_on_bom_confirmed_by_id             (bom_confirmed_by_id)
#  index_mes_production_orders_on_bom_id                          (bom_id)
#  index_mes_production_orders_on_crm_product_id                  (crm_product_id)
#  index_mes_production_orders_on_crm_sales_order_id              (crm_sales_order_id)
#  index_mes_production_orders_on_gm_id                           (gm_id)
#  index_mes_production_orders_on_manager_id                      (manager_id)
#  index_mes_production_orders_on_owner_id                        (owner_id)
#  index_mes_production_orders_on_stage_ack_by_id                 (stage_ack_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_confirmed_by_id => users.id) ON DELETE => nullify
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

  # 审批链（取代「发布」）：业务员提交 → 部门主管 → 总经理，全部通过才正式生效。
  # DRAFT 草稿(仅本人) / SUBMITTED 待部门主管 / MANAGER_APPROVED 待总经理 /
  # APPROVED 通过(生效·下游可见) / REJECTED 驳回(退回业务员可改后重提)。
  APPROVAL_STATUSES = %w[DRAFT SUBMITTED MANAGER_APPROVED APPROVED REJECTED].freeze

  # 每个阶段对应的前端板块（board_key），用于查该阶段负责人（Mes::BoardOwner）。
  # SALES_CONFIRMED（建单）由各业务自建、无统一板块负责人，不入接单机制；SHIPPED 为终点无需接单。
  STAGE_BOARD_KEYS = {
    'BOM_READY' => 'mes_boms_index',
    'PURCHASING' => 'mes_purchase_orders_index',
    'MATERIAL_INBOUND' => 'mes_stock_entries_index',
    'PICKING' => 'mes_material_issues_index',
    'PRODUCTION' => 'mes_production_records_index',
    'FG_INBOUND' => 'mes_fg_inbound_index'
  }.freeze

  # 阶段中文名（用于站内通知文案）。
  STAGE_LABELS = {
    'SALES_CONFIRMED' => '销售订单确定',
    'BOM_READY' => '工程/PMC BOM',
    'PURCHASING' => '采购原料',
    'MATERIAL_INBOUND' => '原料入库',
    'PICKING' => '生产领料',
    'PRODUCTION' => '生产',
    'FG_INBOUND' => '成品入库',
    'SHIPPED' => '销售出库'
  }.freeze

  # 接单时限：进入阶段后 N 小时内负责人须接单，超时即「未接单超时」并可升级。
  ACK_LIMIT_HOURS = 4

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :bom, class_name: 'Mes::Bom', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :stage_ack_by, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true # 部门主管（审批一级）
  belongs_to :gm, class_name: 'User', optional: true      # 总经理（审批二级）
  belongs_to :bom_confirmed_by, class_name: 'User', optional: true # 业务二次确认 BOM 的人
  has_many :stage_events, class_name: 'Mes::ProductionOrderStageEvent', dependent: :destroy, inverse_of: :production_order

  audited except: %i[created_at updated_at], on: %i[create update]
  has_many_attached :images # 产品图片（缩略展示）
  has_many_attached :files  # 附件（合同/文档等）

  after_create :mark_sales_order_in_production
  after_create :record_initial_stage
  # is_draft 由审批状态派生：仅 APPROVED 才是正式（非草稿），下游可见。
  before_save :sync_draft_from_approval

  validates :product_name, presence: true
  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  # 产品编码（工程/PMC 编，供 ERP 共享）：允许同款产品多单共用一个编码，不做唯一约束。
  validates :qty, presence: true, numericality: { greater_than: 0 }
  validates :stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  scope :active, -> { where.not(status: 'CANCELLED') }
  # 已发布（非草稿）：看板/预警/待接单等全局视图只看已发布。
  scope :published, -> { where(is_draft: false) }
  # 列表可见：已发布对全员可见；草稿仅创建人（owner）可见。
  scope :visible_to, ->(user) { where('NOT is_draft OR owner_id = :uid', uid: user&.id) }
  # 审批收件箱：停在我这一级待办的单。
  scope :awaiting_manager_for, ->(uid) { where(approval_status: 'SUBMITTED', manager_id: uid) }
  scope :awaiting_gm_for, ->(uid) { where(approval_status: 'MANAGER_APPROVED', gm_id: uid) }

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
    changed = stage != new_stage
    update_columns(stage: new_stage, stage_ack_at: nil, stage_ack_by_id: nil, updated_at: at) if changed
    stage_events.find_or_create_by!(stage: new_stage) do |e|
      e.account_id = account_id
      e.entered_at = at
      e.actor_id = actor&.id
    end
    notify_stage_assigned(actor) if changed
    self
  end

  # 挂工程 BOM（阶段 2）：绑 BOM、按预估交期天数算预估完工、进 BOM_READY。
  # planned_end 显式传入则优先；否则用 BOM 的 estimated_lead_days 从今天推算。
  # 挂 BOM 会重置「业务二次确认」（含改挂/换 BOM）：新 BOM 须业务重新核对确认。
  # 进 BOM_READY 后通知业务员二次确认；确认前不得下发采购。
  def attach_bom!(bom, planned_end: nil, actor: nil)
    planned = planned_end.presence
    lead = bom.total_lead_days
    planned ||= lead.positive? ? lead.days.from_now : nil
    updates = { bom_id: bom.id, bom_confirmed_at: nil, bom_confirmed_by_id: nil }
    updates[:planned_end_date] = planned if planned
    update!(updates)
    enter_stage!('BOM_READY', actor: actor) if stage == 'SALES_CONFIRMED'
    notify_bom_reconfirm(bom)
    self
  end

  def bom_confirmed? = bom_confirmed_at.present?

  # 业务二次确认 BOM（BOM_READY 段内的一道闸）：核对工程做的用料清单后确认，
  # 确认后 PMC 方可下发采购。确认时回通知 BOM 板块负责人。
  def confirm_bom!(actor)
    raise StandardError, '需先挂工程/PMC BOM' if bom_id.nil?
    raise StandardError, '非「工程/PMC BOM」环节，无法确认' unless stage == 'BOM_READY'
    raise StandardError, 'BOM 已确认，无需重复' if bom_confirmed_at.present?

    update!(bom_confirmed_at: Time.current, bom_confirmed_by_id: actor&.id)
    notify_stage_owners(
      kind: 'bom_confirmed',
      title: "BOM 已二次确认：生产订单 #{order_no}",
      body: "#{actor&.name || '业务'} 已确认 BOM #{bom&.bom_no}，可下发采购。"
    )
    self
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING），通知采购备料。
  # 需业务二次确认 BOM 后才放行。
  def release_to_purchasing!(actor: nil)
    raise StandardError, '需先挂工程/PMC BOM' if bom_id.nil?
    raise StandardError, '当前阶段无法下发采购' unless stage == 'BOM_READY'
    raise StandardError, '需业务二次确认 BOM 后方可下发采购' if bom_confirmed_at.nil?

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
  # category 传入则只展开该类用料（MACHINE 整机 / PACKAGING 包装）；
  # 生产领料只推整机物料（包装未到不挡开产），采购需全推。
  def material_requirements(category: nil)
    return [] if bom.nil? || bom.base_qty.to_d.zero?

    factor = qty.to_d / bom.base_qty.to_d
    items = bom.bom_items
    items = items.select { |i| i.category == category } if category.present?
    items.map { |item| requirement_row(item, factor) }
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

  # 指定板块的负责人 user_id。
  def board_owner_ids(board_key)
    account.mes_board_owners.find_by(board_key: board_key)&.manager_ids || []
  end

  # 当前阶段负责人的 user_id（取该阶段板块负责人）。
  def current_stage_owner_ids
    key = STAGE_BOARD_KEYS[stage]
    key ? board_owner_ids(key) : []
  end

  # 生产报工后通知仓库来做成品入库（全部/部分完工都推）。
  def notify_fg_inbound_ready(reported_qty, actor: nil)
    owner_ids = board_owner_ids('mes_fg_inbound_index')
    return if owner_ids.blank?

    done = produced_qty.to_d >= qty.to_d
    Mes::Notifier.notify(
      account: account, recipients: owner_ids, kind: 'production_reported',
      title: "待成品入库：#{order_no}（#{done ? '已完工' : '部分完工'}）",
      body: "#{actor&.name || '生产'} 报工 #{fnum(reported_qty)} #{unit}，累计 #{fnum(produced_qty)}/#{fnum(qty)}，请安排成品入库。",
      order: self
    )
  end

  # 当前阶段负责人姓名（点名展示用；未配置则为空）。
  def current_stage_owner_names
    ids = current_stage_owner_ids
    ids.blank? ? [] : account.users.where(id: ids).pluck(:name)
  end

  # 接单：标记谁在何时接手（update! 触发审计留痕）。
  # 同时把接单时刻/接单人落到本阶段事件上——订单推进后 stage_ack_at 会清零，
  # 阶段事件留痕才能供看板「各环节接单响应时长」按周期统计。
  def acknowledge!(actor)
    raise StandardError, '当前阶段无需接单' unless awaiting_ack?

    now = Time.current
    update!(stage_ack_at: now, stage_ack_by_id: actor&.id)
    stage_events.where(stage: stage).update_all(acked_at: now, acked_by_id: actor&.id, updated_at: now)
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
      # 退回即重新计时、须重新接单，清掉上一阶段旧的接单留痕。
      ev.update!(entered_at: now, actor_id: actor&.id, note: "被下游退回：#{reason}", acked_at: nil, acked_by_id: nil)
    end
    notify_stage_owners(
      kind: 'stage_returned',
      title: "被下游退回：#{STAGE_LABELS[stage]}",
      body: "生产订单 #{order_no}（#{product_name}）被下游退回本阶段：#{reason}"
    )
    self
  end

  # ── 审批链（取代发布）：业务员提交 → 部门主管 → 总经理 ──

  # 是否处于待审批（某一级待办中）。
  def pending_approval?
    %w[SUBMITTED MANAGER_APPROVED].include?(approval_status)
  end

  # 当前待审批人（下一个该点的人）。
  def current_approver_id
    case approval_status
    when 'SUBMITTED' then manager_id
    when 'MANAGER_APPROVED' then gm_id
    end
  end

  # 提交审批：解析部门主管与总经理并落库；无主管则直接进「待总经理」。
  # 重提（REJECTED）会清掉上一轮的审批留痕，重走全程。
  def submit_for_approval!(_actor)
    raise StandardError, '当前状态无法提交审批' unless %w[DRAFT REJECTED].include?(approval_status)

    self.manager_id = resolve_manager_id
    self.gm_id = resolve_gm_id
    self.submitted_at = Time.current
    self.manager_acted_at = self.manager_comment = nil
    self.gm_acted_at = self.gm_comment = nil
    self.approval_status = manager_id.present? ? 'SUBMITTED' : 'MANAGER_APPROVED'
    save!
    notify_approval_pending
    self
  end

  # 部门主管通过 → 待总经理。
  def manager_approve!(actor, comment: nil)
    raise StandardError, '非「待部门主管」环节' unless approval_status == 'SUBMITTED'

    update!(approval_status: 'MANAGER_APPROVED', manager_id: actor.id,
            manager_acted_at: Time.current, manager_comment: comment)
    notify_approval_pending
    self
  end

  # 总经理通过 → 正式生效（is_draft 随之转 false，进入生产流转、下游可见）。
  def gm_approve!(actor, comment: nil)
    raise StandardError, '非「待总经理」环节' unless approval_status == 'MANAGER_APPROVED'

    update!(approval_status: 'APPROVED', gm_id: actor.id,
            gm_acted_at: Time.current, gm_comment: comment)
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'approval_approved',
      title: "审批通过：生产订单 #{order_no}",
      body: '总经理已通过，订单已生效并进入生产流转。', order: self
    )
    self
  end

  # 驳回：记录当前级别的审批人与原因，退回业务员（REJECTED，可改后重提）。
  def reject_approval!(actor, reason:)
    raise StandardError, '当前状态无法驳回' unless pending_approval?

    if approval_status == 'SUBMITTED'
      self.manager_id = actor.id
      self.manager_acted_at = Time.current
      self.manager_comment = reason
    else
      self.gm_id = actor.id
      self.gm_acted_at = Time.current
      self.gm_comment = reason
    end
    self.approval_status = 'REJECTED'
    save!
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'approval_rejected',
      title: "审批被驳回：生产订单 #{order_no}",
      body: "驳回原因：#{reason}", order: self
    )
    self
  end

  private

  # 数量文案：去掉多余小数（50.0 → 50）。
  def fnum(value)
    format('%g', value.to_f)
  end

  # 单行用料需求（用量按本单产量/基准产量放大）。
  def requirement_row(item, factor)
    {
      mes_material_id: item.mes_material_id,
      material_no: item.material_no,
      material_name: item.material_name,
      specification: item.specification,
      unit: item.unit,
      category: item.category,
      qty: (item.qty.to_d * factor)
    }
  end

  # ── 站内通知埋点 ──

  # 进入需接单的下游阶段时通知该阶段负责人（BOM_READY 例外：其待办是业务二次确认）。
  def notify_stage_assigned(actor)
    return unless STAGE_BOARD_KEYS.key?(stage)
    return if stage == 'BOM_READY'

    label = STAGE_LABELS[stage]
    notify_stage_owners(
      kind: 'stage_assigned',
      title: "待接单：#{label}",
      body: "生产订单 #{order_no}（#{product_name}）进入#{label}阶段，请及时接单。",
      exclude: actor&.id
    )
  end

  # 通知当前阶段负责人（可排除触发者本人）。
  def notify_stage_owners(kind:, title:, body:, exclude: nil)
    recipients = current_stage_owner_ids - [exclude].compact
    Mes::Notifier.notify(account: account, recipients: recipients, kind: kind, title: title, body: body, order: self)
  end

  # 挂 BOM 后通知业务员二次确认。
  def notify_bom_reconfirm(bom)
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'bom_reconfirm',
      title: "待二次确认BOM：生产订单 #{order_no}",
      body: "工程/PMC 已挂 BOM #{bom.bom_no}，请核对用料后点「确认BOM」，确认后方可下发采购。",
      order: self
    )
  end

  # 提交/主管通过后通知下一级审批人。
  def notify_approval_pending
    role = approval_status == 'SUBMITTED' ? '部门主管' : '总经理'
    body = approval_status == 'SUBMITTED' ? "#{owner&.name || '业务员'} 提交了生产订单，待你审批。" : '部门主管已通过，待你审批。'
    Mes::Notifier.notify(
      account: account, recipients: current_approver_id, kind: 'approval_pending',
      title: "待审批：生产订单 #{order_no}（#{role}）", body: body, order: self
    )
  end

  def product_line_source = crm_product

  # 仅 APPROVED 视为正式（非草稿）；其余审批态均为草稿、下游不可见。
  def sync_draft_from_approval
    self.is_draft = (approval_status != 'APPROVED')
  end

  # 业务员所在（主）部门的负责人=部门主管；本人即负责人则向上找上级部门负责人。
  def resolve_manager_id
    return nil if owner_id.nil?

    membership = account.org_memberships.where(user_id: owner_id).order(is_primary: :desc, id: :asc).first
    dept = membership && account.org_departments.find_by(id: membership.department_id)
    while dept
      return dept.leader_id if dept.leader_id.present? && dept.leader_id != owner_id

      dept = dept.parent_id && account.org_departments.find_by(id: dept.parent_id)
    end
    nil
  end

  # 总经理=绩效设置里指定的那位（与 KPI 同一人）。
  def resolve_gm_id
    Crm::PerformanceSetting.for_account(account)&.gm_owner_id
  end

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
