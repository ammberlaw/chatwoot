# == Schema Information
#
# Table name: mes_production_orders
#
#  id                    :bigint           not null, primary key
#  actual_end_date       :datetime
#  actual_start_date     :datetime
#  approval_status       :string           default("DRAFT"), not null
#  bom_confirmed_at      :datetime
#  delivery_date         :datetime
#  gm_acted_at           :datetime
#  gm_comment            :text
#  is_draft              :boolean          default(FALSE), not null
#  is_outsourced         :boolean          default(FALSE), not null
#  manager_acted_at      :datetime
#  manager_comment       :text
#  order_kind            :string           default("CUSTOMER"), not null
#  order_no              :string           not null
#  pi_no                 :string
#  planned_end_date      :datetime
#  planned_start_date    :datetime
#  produced_qty          :decimal(14, 3)   default(0.0), not null
#  product_code          :string
#  product_line          :string
#  product_name          :string           not null
#  qty                   :decimal(14, 3)   not null
#  remark                :text
#  spec                  :jsonb            not null
#  stage                 :string           default("SALES_CONFIRMED"), not null
#  stage_ack_at          :datetime
#  status                :string           default("IN_PROGRESS"), not null
#  submitted_at          :datetime
#  unit                  :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  bom_confirmed_by_id   :bigint
#  bom_id                :bigint
#  crm_customer_id       :bigint
#  crm_product_id        :bigint
#  crm_sales_order_id    :bigint
#  gm_id                 :bigint
#  manager_id            :bigint
#  outsource_supplier_id :bigint
#  owner_id              :bigint
#  stage_ack_by_id       :bigint
#
# Indexes
#
#  index_mes_production_orders_on_account_and_product_code        (account_id,product_code)
#  index_mes_production_orders_on_account_and_product_line        (account_id,product_line)
#  index_mes_production_orders_on_account_id                      (account_id)
#  index_mes_production_orders_on_account_id_and_approval_status  (account_id,approval_status)
#  index_mes_production_orders_on_account_id_and_is_draft         (account_id,is_draft)
#  index_mes_production_orders_on_account_id_and_is_outsourced    (account_id,is_outsourced)
#  index_mes_production_orders_on_account_id_and_order_kind       (account_id,order_kind)
#  index_mes_production_orders_on_account_id_and_order_no         (account_id,order_no) UNIQUE
#  index_mes_production_orders_on_account_id_and_stage            (account_id,stage)
#  index_mes_production_orders_on_bom_confirmed_by_id             (bom_confirmed_by_id)
#  index_mes_production_orders_on_bom_id                          (bom_id)
#  index_mes_production_orders_on_crm_customer_id                 (crm_customer_id)
#  index_mes_production_orders_on_crm_product_id                  (crm_product_id)
#  index_mes_production_orders_on_crm_sales_order_id              (crm_sales_order_id)
#  index_mes_production_orders_on_gm_id                           (gm_id)
#  index_mes_production_orders_on_manager_id                      (manager_id)
#  index_mes_production_orders_on_outsource_supplier_id           (outsource_supplier_id)
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

  # 外购按单短版脊柱：工程判定为外购成品后跳过 BOM/领料/报工/质检，
  # 只走 销售订单确定 → 采购 → 成品入库 → 出库（用于时间线展示与阶段推进）。
  OUTSOURCE_STAGES = %w[SALES_CONFIRMED PURCHASING FG_INBOUND SHIPPED].freeze

  # 生命周期（与 stage 正交）。
  STATUSES = %w[IN_PROGRESS COMPLETED STOPPED CANCELLED].freeze

  # 订单性质：CUSTOMER 按单生产（归属业务员收敛，只归属自己可见）；
  # STOCK 外贸备货生产（建公司共享库存，全业务可见；owner 复用为「责任人」不做收敛）。
  ORDER_KINDS = %w[CUSTOMER STOCK].freeze

  # 审批链（取代「发布」）：业务员提交 → 部门主管 → 总经理，全部通过才正式生效。
  # DRAFT 草稿(仅本人) / SUBMITTED 待部门主管 / MANAGER_APPROVED 待总经理 /
  # APPROVED 通过(生效·下游可见) / REJECTED 驳回(退回业务员可改后重提)。
  APPROVAL_STATUSES = %w[DRAFT SUBMITTED MANAGER_APPROVED APPROVED REJECTED].freeze

  # 每个阶段对应的前端板块（board_key），用于查该阶段负责人（Mes::BoardOwner）。
  # SALES_CONFIRMED（建单生效）归工程/PMC 板块——订单生效后工程/PMC 须接单出 BOM，
  # 纳入接单机制（待接单/超时/升级），堵住"无人认领长期卡单"；SHIPPED 为终点无需接单。
  STAGE_BOARD_KEYS = {
    'SALES_CONFIRMED' => 'mes_boms_index',
    'BOM_READY' => 'mes_boms_index',
    'PURCHASING' => 'mes_purchase_orders_index',
    'MATERIAL_INBOUND' => 'mes_stock_entries_index',
    'PICKING' => 'mes_material_issues_index',
    'PRODUCTION' => 'mes_production_records_index',
    'FG_INBOUND' => 'mes_fg_inbound_index'
  }.freeze

  # 板块对应的岗位：把「等谁」写成「工程-朱桂权」时用。
  # 一人身兼多岗（如 PMC+采购）时靠它挑出跟当前板块对得上的那个岗位。
  BOARD_ROLE_HINTS = {
    'mes_boms_index' => %w[engineer pmc],
    'mes_purchase_orders_index' => %w[buyer],
    'mes_stock_entries_index' => %w[warehouse],
    'mes_material_issues_index' => %w[warehouse],
    'mes_production_records_index' => %w[production],
    'mes_fg_inbound_index' => %w[warehouse]
  }.freeze

  # 待办（待我接单）归属映射：在板块映射之外，把无板块的「销售订单确定」
  # 归给 BOM 负责人——新生效待挂 BOM 的单进 PMC/工程待办。仅待办用，不参与接单计时。
  INBOX_BOARD_KEYS = STAGE_BOARD_KEYS.merge('SALES_CONFIRMED' => 'mes_boms_index').freeze

  # 阶段中文名（用于站内通知文案）。
  STAGE_LABELS = {
    'SALES_CONFIRMED' => '待工程接单',
    'BOM_READY' => '工程/PMC 生产任务单',
    'PURCHASING' => '采购原料',
    'MATERIAL_INBOUND' => '原料入库',
    'PICKING' => '生产领料',
    'PRODUCTION' => '生产',
    'FG_INBOUND' => '成品入库',
    'SHIPPED' => '销售出库'
  }.freeze

  # 接单时限：进入阶段后 N 个「工作小时」内负责人须接单（工作日 08:00–17:30、跳周末，
  # 见 config/initializers/working_hours.rb），超时即「超时未接单」并可升级。
  ACK_LIMIT_HOURS = 4

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true # 业务员建单挂 CRM 客户（国家从客户带出）
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :bom, class_name: 'Mes::Bom', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :stage_ack_by, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true # 部门主管（审批一级）
  belongs_to :gm, class_name: 'User', optional: true      # 总经理（审批二级）
  belongs_to :bom_confirmed_by, class_name: 'User', optional: true # 历史字段：原「业务二次确认生产任务单」的人，流程已取消
  belongs_to :outsource_supplier, class_name: 'Mes::Supplier', optional: true # 外购成品供应商（工程指定）
  has_many :stage_events, class_name: 'Mes::ProductionOrderStageEvent', dependent: :destroy, inverse_of: :production_order
  # 接单/转交流水（一个阶段可两人接力，各自留痕；订单上的 stage_ack_* 只表示「当前状态」）
  has_many :stage_ack_events, class_name: 'Mes::StageAckEvent', dependent: :destroy, inverse_of: :production_order
  has_many :order_forwards, -> { order(created_at: :desc) }, class_name: 'Mes::OrderForward', dependent: :destroy, inverse_of: :production_order
  # 一张生产订单可挂多张采购单（如主料/辅料各一张，不同采购员）。
  has_many :purchase_orders, class_name: 'Mes::PurchaseOrder', dependent: :nullify, inverse_of: :production_order

  audited except: %i[created_at updated_at], on: %i[create update]
  has_many_attached :images # 产品图片（缩略展示）
  has_many_attached :files  # 附件（合同/文档等）

  # is_draft 由审批状态派生：仅 APPROVED 才是正式（非草稿），下游可见。
  before_save :sync_draft_from_approval
  after_create :mark_sales_order_in_production
  after_create :record_initial_stage

  validates :product_name, presence: true
  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  # 产品编码（工程/PMC 编，供 ERP 共享）：允许同款产品多单共用一个编码，不做唯一约束。
  validates :qty, presence: true, numericality: { greater_than: 0 }
  validates :stage, inclusion: { in: STAGES }
  validates :status, inclusion: { in: STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
  validates :order_kind, inclusion: { in: ORDER_KINDS }

  scope :active, -> { where.not(status: 'CANCELLED') }
  scope :stock, -> { where(order_kind: 'STOCK') }
  # 已发布（非草稿）：看板/预警/待接单等全局视图只看已发布。
  scope :published, -> { where(is_draft: false) }
  # 列表可见：已发布对全员可见；草稿仅创建人（owner）可见。
  scope :visible_to, ->(user) { where('NOT is_draft OR owner_id = :uid', uid: user&.id) }
  # 审批收件箱：停在我这一级待办的单。
  scope :awaiting_manager_for, ->(uid) { where(approval_status: 'SUBMITTED', manager_id: uid) }
  scope :awaiting_gm_for, ->(uid) { where(approval_status: 'MANAGER_APPROVED', gm_id: uid) }
  # 工单号：WT-下单日期-当天第几单（对齐公司纸质单写法）。
  # 只作用于新建单；已有的 MO-/PO- 号保持原样，改历史号会让纸质单和下游单据全对不上。
  def self.document_number_prefix = 'WT'

  # 备货生产订单（全业务共享库存）。
  def stock? = order_kind == 'STOCK'

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
    rollup_erp_cost if changed && new_stage == 'SHIPPED'
    self
  end

  # 出货即把本单的实际耗用/外协采购归集成 ERP 订单成本，毛利表不再靠人工录。
  # ERP 是下游，不能反过来挡住 MES 出货，所以异常只记日志——财务在成本页还有「一键归集」可补。
  def rollup_erp_cost
    return if crm_sales_order_id.blank?

    Erp::CostRollupService.new(account).sync_production_order(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::CostRollup] 生产订单 #{order_no} 成本归集失败: #{e.message}")
  end

  # 挂工程 BOM（阶段 2）：绑 BOM、按预估交期天数算预估完工、进 BOM_READY。
  # planned_end 显式传入则优先；否则用 BOM 的 estimated_lead_days 从今天推算。
  # 挂 BOM 后直接进 BOM_READY，下一步就是工程/PMC「下发到采购」。
  # （原先中间有一道「业务二次确认 BOM」的闸，已按业务要求取消。）
  def attach_bom!(bom, planned_end: nil, actor: nil)
    # 与 mark_outsourced! 对称：外购单走短脊柱（采购→成品入库→发货），不该再挂 BOM。
    raise StandardError, '外购订单不挂生产任务单；如需自产请先撤销外购标记' if is_outsourced

    planned = planned_end.presence
    lead = bom.total_lead_days
    planned ||= lead.positive? ? lead.days.from_now : nil
    updates = { bom_id: bom.id }
    updates[:planned_end_date] = planned if planned
    update!(updates)
    # 工程建 BOM 常留空产品线；继承订单产品线，否则业务员按产品线筛会漏看这张 BOM。
    bom.update!(product_line: product_line) if bom.product_line.blank? && product_line.present?
    enter_stage!('BOM_READY', actor: actor) if stage == 'SALES_CONFIRMED'
    notify_purchase_release_pending(bom, actor)
    self
  end

  # 挂好 BOM 即是工程/PMC 的待办：发 todo 类通知进其「待处理」，下发采购时自动销掉。
  def notify_purchase_release_pending(bom, actor)
    notify_stage_owners(
      kind: 'purchase_release_pending',
      title: "待下发采购：生产订单 #{order_no}",
      body: "#{actor&.name || '工程'} 已挂生产任务单 #{bom.bom_no}，请核对后点「下发到采购」。"
    )
  end

  # 解除 BOM 关联（挂错 BOM 的纠错口）：清掉 bom_id、退回「待工程接单」重新挂。
  # 已开出下游单据的不许解——先作废那些单，否则采购/仓库会按错料继续做。
  def detach_bom!(actor: nil)
    raise StandardError, '该订单未挂生产任务单' if bom_id.nil?

    ensure_revertable!('解除生产任务单')

    # 挂 BOM 时发的「待下发采购」待办要一并销掉，否则工程/PMC 的待处理里留一条指向空 BOM 的僵尸。
    Mes::Notifier.resolve(account: account, order: self, kinds: 'purchase_release_pending')
    update!(bom_id: nil)
    revert_stage!('SALES_CONFIRMED', actor: actor)
    self
  end

  # 采购原料 → 工程/PMC BOM 的退回（下发早了 / BOM 要改时用）。同样要求下游没单据。
  def revert_to_bom_ready!(actor: nil)
    raise StandardError, '仅「采购原料」阶段可退回' unless stage == 'PURCHASING'
    raise StandardError, '外购订单不走生产任务单阶段，无法退回' if is_outsourced
    raise StandardError, '该订单未挂生产任务单，请改用解除关联' if bom_id.nil?

    ensure_revertable!('退回')

    revert_stage!('BOM_READY', actor: actor)
    # 退回来就还得再走一遍「核对 BOM → 下发采购」，把待办重新挂给工程/PMC。
    notify_purchase_release_pending(bom, actor)
    self
  end

  # 解绑 BOM / 退回阶段前的闸：下游一旦动起来就不许往回改，否则采购和仓库按错料继续做。
  # 报工无法作废（已经开工了），单独先拦；其余单据作废掉就能放行。
  def ensure_revertable!(action)
    raise StandardError, "该订单已有报工记录（已开工），不能#{action}" if account.mes_production_records.where(production_order_id: id).exists?

    blockers = downstream_blockers
    raise StandardError, "已开出#{blockers.join('、')}，请先作废这些单据再#{action}" if blockers.any?
  end

  # 已开出的下游单据（作废的不算）。
  def downstream_blockers
    names = []
    names << '请购单' if account.mes_purchase_requisitions.where(production_order_id: id).where.not(status: 'CANCELLED').exists?
    names << '采购单' if purchase_orders.where.not(status: 'CANCELLED').exists?
    names << '出入库单' if account.mes_stock_entries.where(production_order_id: id).where.not(status: 'CANCELLED').exists?
    names
  end

  # 阶段回退（纠错专用，与 enter_stage! 相对）：退回更早的阶段，并抹掉超前阶段的到达事件，
  # 否则阶段耗时/「已 N 天」会按那次走错的记录算。目标阶段自身的到达时间保留首次到达，
  # 好让看板照旧能看出这单实际卡了多久。
  def revert_stage!(target, actor: nil)
    cur = STAGES.index(stage)
    ref = STAGES.index(target)
    raise StandardError, '目标阶段无效' if cur.nil? || ref.nil?
    raise StandardError, '只能退回更早的阶段' unless ref < cur

    stage_events.where(stage: STAGES[(ref + 1)..]).destroy_all
    update!(stage: target, stage_ack_at: nil, stage_ack_by_id: nil)
    stage_events.find_or_create_by!(stage: target) do |e|
      e.account_id = account_id
      e.entered_at = Time.current
      e.actor_id = actor&.id
    end
    self
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING），通知采购备料。
  def release_to_purchasing!(actor: nil)
    raise StandardError, '需先挂工程/PMC 生产任务单' if bom_id.nil?
    raise StandardError, '当前阶段无法下发采购' unless stage == 'BOM_READY'

    Mes::Notifier.resolve(account: account, order: self, kinds: 'purchase_release_pending')
    enter_stage!('PURCHASING', actor: actor)
    self
  end

  # 齐套判定：本单所有关联（未作废）采购单都到料齐（RECEIVED）才算采购完成，方可从
  # 「采购原料」推进到「原料入库」。一单多采购单（主料/辅料分采购）时防某张先到就开工。
  # 无关联采购单时不设闸（沿用旧行为：收货即推进，避免回退直接开料的订单）。
  def purchase_complete?
    pos = purchase_orders.where.not(status: 'CANCELLED')
    return true if pos.empty?

    pos.all? { |po| po.status == 'RECEIVED' }
  end

  def outsourced? = is_outsourced

  # 流程闸用：订单是否已走到（或越过）某阶段。用于「下游单必须等上游做完才能开」的硬锁，
  # 杜绝越级开单（如没领料/没报工就开成品入库）。按 STAGES 顺序比较（外购阶段是其子集，同样适用）。
  def stage_reached?(target)
    cur = STAGES.index(stage)
    ref = STAGES.index(target)
    !cur.nil? && !ref.nil? && cur >= ref
  end

  # 工程判定为「外购成品」：选定产品+供应商，跳过 BOM 直接进采购阶段（短版脊柱）。
  # 只在建单阶段（SALES_CONFIRMED）可标记。
  def mark_outsourced!(crm_product_id:, supplier_id:, product_name: nil, actor: nil)
    raise StandardError, '仅「销售订单确定」阶段可标记外购' unless stage == 'SALES_CONFIRMED'
    raise StandardError, '该订单已挂生产任务单，不能标记为外购；请先撤销生产任务单再改外购' if bom_id.present?

    updates = { is_outsourced: true, crm_product_id: crm_product_id, outsource_supplier_id: supplier_id }
    updates[:product_name] = product_name if product_name.present?
    update!(updates)
    # 直接进采购阶段——enter_stage! 会通知采购板块负责人接单。
    enter_stage!('PURCHASING', actor: actor)
    self
  end

  # 报工累加已产数量；首次「有实际产出」的报工才把阶段从「生产领料」推进到「生产」。
  # 用原子 SQL 自增，避免并发报工读-改-写丢更新；零产出的空报工不推进阶段（否则无产出即解锁成品入库）。
  def add_produced!(delta)
    self.class.where(id: id).update_all(['produced_qty = produced_qty + ?, updated_at = ?', delta.to_d, Time.current])
    reload
    enter_stage!('PRODUCTION') if stage == 'PICKING' && produced_qty.to_d.positive?
  end

  # 删除报工时回退已产数量（如清理重复报工）；下限 0，原子扣减。
  # 回退后若已产已低于订单量而订单曾标「已完成」，退回「进行中」；
  # 若已产归零且尚无成品入库，阶段从「生产」退回「生产领料」，避免「产量 0 却在生产阶段」的脏态。
  def remove_produced!(delta)
    self.class.where(id: id).update_all(['produced_qty = GREATEST(produced_qty - ?, 0), updated_at = ?', delta.to_d, Time.current])
    reload
    update_columns(status: 'IN_PROGRESS', updated_at: Time.current) if status == 'COMPLETED' && produced_qty.to_d < qty.to_d
    return unless stage == 'PRODUCTION' && produced_qty.to_d.zero? && fg_inbound_qty.to_d.zero?

    enter_stage!('PICKING', at: Time.current)
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
    product_map = crm_product_map_for(items)
    stock_map = onhand_total_map(product_map.values)
    ordered = ordered_qty_map
    items.map { |item| requirement_row(item, factor, product_map, stock_map, ordered) }
  end

  # 哪些订单的料已经都下满采购单了（返回 id 的 Set）。
  # 口径与算料页一致：需求量 = BOM 行用量 × 订单量/基准量，已下量按产品档案归集；
  # 但不查库存——这里只回答「还有没有料要下单」。
  # 没挂 BOM、BOM 没行、基准量为 0 的单都不算「下完」（料还没定出来，不能从候选里拿掉）。
  # 批量算：采购单的「关联生产订单」下拉一次拉几百张，逐张展开 BOM 就是上千条 SQL。
  def self.bulk_purchasing_complete(account, orders)
    candidates = orders.select { |o| o.bom_id.present? }
    return Set.new if candidates.empty?

    rows_by_bom = bom_item_rows_by_bom(candidates.map(&:bom_id))
    product_ids = crm_product_ids_for_rows(account, rows_by_bom)
    ordered = bulk_ordered_qty(candidates.map(&:id))
    candidates.filter_map { |o| o.id if rows_all_ordered?(o, rows_by_bom[o.bom_id], product_ids, ordered[o.id]) }.to_set
  end

  def self.rows_all_ordered?(order, rows, product_ids, placed)
    factor = order.bom.base_qty.to_d.zero? ? 0 : order.qty.to_d / order.bom.base_qty.to_d
    return false if rows.blank? || factor.zero?

    placed ||= {}
    rows.all? { |(material_no, item_qty)| row_ordered?(product_ids[material_no], placed, item_qty.to_d * factor) }
  end

  def self.row_ordered?(crm_product_id, placed, required_qty)
    crm_product_id.present? && (placed[crm_product_id] || 0).to_d >= required_qty
  end

  def self.bom_item_rows_by_bom(bom_ids)
    Mes::BomItem.where(bom_id: bom_ids).pluck(:bom_id, :material_no, :qty)
                .group_by(&:first)
                .transform_values { |rows| rows.map { |r| [r[1], r[2]] } }
  end

  # BOM 行的料号 → 产品档案 id（已下采购量是按产品档案归集的，要靠这层对上）。
  def self.crm_product_ids_for_rows(account, rows_by_bom)
    codes = rows_by_bom.values.flatten(1).filter_map(&:first).uniq
    return {} if codes.empty?

    Crm::Product.where(account_id: account.id, sku: codes).pluck(:sku, :id).to_h
  end

  # { production_order_id => { crm_product_id => 已下采购量 } }，作废单不算。
  def self.bulk_ordered_qty(order_ids)
    Mes::PurchaseItem
      .joins(:purchase_order)
      .where(mes_purchase_orders: { production_order_id: order_ids })
      .where.not(mes_purchase_orders: { status: 'CANCELLED' })
      .where.not(crm_product_id: nil)
      .group('mes_purchase_orders.production_order_id', :crm_product_id)
      .sum(:qty)
      .each_with_object({}) { |((po_id, pid), sum), acc| (acc[po_id] ||= {})[pid] = sum }
  end

  # 本单已经开出去的采购量（按产品档案归集，作废单不算）。
  # 采购员重进「新建采购单」时，已下满的料就不再铺出来——否则整屏都是料，看不出哪些还没下。
  def ordered_qty_map
    Mes::PurchaseItem
      .joins(:purchase_order)
      .where(mes_purchase_orders: { production_order_id: id })
      .where.not(mes_purchase_orders: { status: 'CANCELLED' })
      .where.not(crm_product_id: nil)
      .group(:crm_product_id)
      .sum(:qty)
  end

  # 指定产品档案的各仓实时结存合计（跨仓总库存）。供采购算料展示「对应物料实时库存」。
  def onhand_total_map(product_ids)
    ids = product_ids.compact.uniq
    return {} if ids.empty?

    Mes::StockBalance.where(account_id: account_id, crm_product_id: ids)
                     .group(:crm_product_id).sum(:qty)
  end

  # 生产领料计划：在 BOM 推料基础上，补每行「已领量 / 实时库存 / 待领量」（供领料页展示）。
  # warehouse_id 传入则算该仓实时库存；已领量按本订单已过账的领料单累计（按产品档案 crm_product_id）。
  def issue_plan(warehouse_id: nil, category: 'MACHINE')
    reqs = material_requirements(category: category)
    issued = issued_qty_map
    onhand = warehouse_id.present? ? onhand_qty_map(warehouse_id) : {}
    reqs.map do |r|
      pid = r[:crm_product_id]
      iss = pid ? (issued[pid] || 0).to_d : 0.to_d
      req = r[:qty].to_d
      r.merge(
        required_qty: req,
        issued_qty: iss,
        on_hand: pid ? (onhand[pid] || 0).to_d : 0.to_d,
        pending_qty: [req - iss, 0].max
      )
    end
  end

  # 本订单已领量（按产品档案）：已过账的领料单明细累计。
  def issued_qty_map
    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(mes_stock_entries: { production_order_id: id, purpose: 'MATERIAL_ISSUE', status: 'POSTED' })
      .where.not(crm_product_id: nil)
      .group(:crm_product_id).sum(:qty)
  end

  # 本订单已完工入库累计量（已过账的成品入库单明细）。用于判定「入库收齐」→ 标记生产完成。
  def fg_inbound_qty
    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(mes_stock_entries: { production_order_id: id, purpose: 'MANUFACTURE', status: 'POSTED' })
      .where(item_type: 'PRODUCT')
      .sum(Arel.sql('COALESCE(received_qty, qty)'))
  end

  # 批量版：列表一次渲染几百张订单，逐张调 #fg_inbound_qty 就是几百条 SQL。
  # 返回 { production_order_id => 已入库量 }，没入过的订单不在键里。
  def self.bulk_fg_inbound_qty(account, order_ids)
    return {} if order_ids.blank?

    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(mes_stock_entries: { account_id: account.id, production_order_id: order_ids,
                                  purpose: 'MANUFACTURE', status: 'POSTED' })
      .where(item_type: 'PRODUCT')
      .group('mes_stock_entries.production_order_id')
      .sum(Arel.sql('COALESCE(mes_stock_entry_items.received_qty, mes_stock_entry_items.qty)'))
  end

  # 入库是否收齐（已完工入库量 ≥ 订单数量）。
  def fg_inbound_complete?
    qty.to_d.positive? && fg_inbound_qty >= qty.to_d
  end

  # 指定仓库的成品/物料实时结存（按产品档案）。
  def onhand_qty_map(warehouse_id)
    Mes::StockBalance
      .where(account_id: account_id, warehouse_id: warehouse_id)
      .where.not(crm_product_id: nil)
      .group(:crm_product_id).sum(:qty)
  end

  # BOM 料号 → 产品档案 id 映射：料号对上产品 sku 时带回，供生产领料按产品档案自动选料。
  def crm_product_map_for(items)
    codes = items.filter_map(&:material_no).uniq
    return {} if codes.empty?

    Crm::Product.where(account_id: account_id, sku: codes).pluck(:sku, :id).to_h
  end

  # ── 接单确认（P1）：接单只是「表态」，不阻塞流程；计时始终以进入阶段时间为准 ──

  # 当前阶段的到达时间（本阶段最近一次进入）。
  def stage_entered_at
    stage_events.select { |e| e.stage == stage }.map(&:entered_at).compact.max
  end

  # 本阶段需要接单吗？终点（SHIPPED，无 board_key）、草稿/审批中、非进行中订单不需要。
  # 建单阶段仅在审批「生效」后才计接单（审批期间是草稿，计时从生效起算，见 activate_stage_ack!）。
  def ack_required?
    status == 'IN_PROGRESS' && !is_draft && STAGE_BOARD_KEYS.key?(stage)
  end

  def awaiting_ack?
    ack_required? && stage_ack_at.nil?
  end

  # 接单截止 = 进入阶段后 ACK_LIMIT_HOURS 个「工作小时」（工作日 08:00–17:30，跳过周末）。
  def ack_deadline
    entered = stage_entered_at
    entered && WorkingHours.add_hours(entered, ACK_LIMIT_HOURS)
  end

  # 未接单超时（装死）：到点还没接单。用于点名 + 升级，不看是否配了负责人。
  def ack_overdue?
    awaiting_ack? && ack_deadline.present? && ack_deadline < Time.current
  end

  # 指定板块的负责人 user_id，按产品线路由（默认取本单所属线）：
  # 优先该产品线专属负责人；未配则回落「全部产线」(product_line '') 通用负责人。
  # 现有调用（通知/待办/点名）不传 line 即自动按本单 product_line 分流。
  def board_owner_ids(board_key, line = product_line)
    rows = account.mes_board_owners.where(board_key: board_key).to_a
    specific = line.present? ? rows.find { |r| r.product_line == line }&.manager_ids : nil
    return specific if specific.present?

    rows.find { |r| r.product_line.blank? }&.manager_ids || []
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

  # 当前阶段负责人姓名（点名展示用；未配置则为空）。带岗位——「工程-朱桂权」。
  def current_stage_owner_names
    staff_names.for_ids(current_stage_owner_ids, BOARD_ROLE_HINTS[STAGE_BOARD_KEYS[stage]])
  end

  # 人名带岗位的统一口径（看板/单据详情/转发目标共用，见 Mes::StaffNames）。
  def staff_names
    @staff_names ||= Mes::StaffNames.new(account)
  end

  # ── 业务知会/转发：把订单转发给某阶段负责人（选板块）+ 附言，推站内通知并在订单上留痕 ──
  # 转发可选的目标板块（去重后的阶段板块）+ 中文名，供前端下拉选人。
  FORWARD_BOARD_LABELS = {
    'mes_boms_index' => '工程/PMC（生产任务单）',
    'mes_purchase_orders_index' => '采购',
    'mes_stock_entries_index' => '原料入库（仓库）',
    'mes_material_issues_index' => '生产领料（仓库）',
    'mes_production_records_index' => '生产/车间',
    'mes_fg_inbound_index' => '成品入库（仓库）'
  }.freeze

  # 各可转发板块当前负责人姓名（无负责人的板块也返回，前端置灰/提示未配置）。
  def forward_targets
    FORWARD_BOARD_LABELS.map do |board_key, label|
      ids = board_owner_ids(board_key)
      { board_key: board_key, label: label,
        recipient_names: staff_names.for_ids(ids, BOARD_ROLE_HINTS[board_key]) }
    end
  end

  # 转发给某板块负责人：落一条通知（每人一条）+ 一条订单留痕。返回留痕记录。
  def forward_to_board!(sender:, board_key:, note:)
    label = FORWARD_BOARD_LABELS[board_key]
    raise ArgumentError, '无效的转发目标' if label.blank?

    recipient_ids = board_owner_ids(board_key)
    raise ArgumentError, "「#{label}」还没有配置负责人" if recipient_ids.blank?

    names = account.users.where(id: recipient_ids).pluck(:name)
    text = note.to_s.strip
    Mes::Notifier.notify(
      account: account, recipients: recipient_ids, kind: 'forwarded',
      title: "订单知会：#{order_no}（#{label}）",
      body: "#{sender&.name || '业务'} 把生产订单 #{order_no}（#{product_name}）知会给你#{text.present? ? "：#{text}" : '。'}",
      order: self
    )
    order_forwards.create!(
      account: account, sender: sender, board_key: board_key,
      stage_label: label, recipient_names: names.join('、'), note: text.presence
    )
  end

  # BOM 变更（工程改动已下发 BOM 的用料）后，通知本单「已参与过的所有下游部门」+ 业务员。
  # 收件人 = 订单已到达过的各阶段板块负责人（采购/仓库/领料/车间…）∪ 业务员，排除改动者本人。
  def notify_bom_revised(summary, rev_no, actor: nil)
    reached_keys = stage_events.map(&:stage).uniq.filter_map { |s| STAGE_BOARD_KEYS[s] }.uniq
    owner_ids = reached_keys.flat_map { |k| board_owner_ids(k) }
    recipients = (owner_ids + [owner_id]).compact.uniq - [actor&.id].compact
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'bom_revised',
      title: "生产任务单已变更（v#{rev_no}）：生产订单 #{order_no}",
      body: "工程调整了生产任务单 #{bom&.bom_no} 用料：#{summary}。#{affected_documents_hint}",
      order: self
    )
  end

  # 改料时这张单已经开出去的单据。只发通知不够用——收通知的人还得自己去翻
  # 有没有已下的采购、已领的料。这里直接把单号列出来，谁该动一目了然。
  # 已取消的不算；采购单连草稿也列（草稿改起来最省事，正好赶在下发前改掉）。
  def affected_documents_hint
    docs = []
    pos = purchase_orders.where.not(status: 'CANCELLED').pluck(:po_no)
    docs << "采购单 #{pos.join('、')}" if pos.any?
    entries = Mes::StockEntry.where(production_order_id: id).where.not(status: 'CANCELLED').pluck(:entry_no)
    docs << "出入库单 #{entries.join('、')}" if entries.any?
    return '这张单还没开出采购/领料单据，改动无下游影响。' if docs.empty?

    "本单已开：#{docs.join('；')}——请复核是否需要同步调整。"
  end

  # 已下发订单被归属业务改单后，通知当前阶段（下一个流程）板块负责人，让其知悉单子有变动。
  # 终点（SHIPPED）无下游、草稿不通知（草稿下游不可见）。
  def notify_order_revised(actor: nil)
    return if is_draft || stage == 'SHIPPED'

    recipients = current_stage_owner_ids - [actor&.id].compact
    return if recipients.blank?

    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'order_revised',
      title: "订单已修改：#{order_no}",
      body: "#{actor&.name || '业务'} 修改了生产订单 #{order_no}（#{product_name}），请复核当前#{STAGE_LABELS[stage]}环节。",
      order: self
    )
  end

  # 接单：标记谁在何时接手（update! 触发审计留痕）。
  # 同时把接单时刻/接单人落到本阶段事件上——订单推进后 stage_ack_at 会清零，
  # 阶段事件留痕才能供看板「各环节接单响应时长」按周期统计。
  def acknowledge!(actor)
    raise StandardError, '当前阶段无需接单' unless awaiting_ack?

    now = Time.current
    update!(stage_ack_at: now, stage_ack_by_id: actor&.id)
    stage_events.where(stage: stage).update_all(acked_at: now, acked_by_id: actor&.id, updated_at: now)
    stage_ack_events.create!(account: account, stage: stage, kind: Mes::StageAckEvent::ACK,
                             actor: actor, happened_at: now) if actor
    Mes::Notifier.resolve(account: account, order: self, kinds: 'stage_assigned')
    self
  end

  # 转给同阶段另一位负责人（工程出完/改完 BOM 转 PMC 投单；反向也允许——
  # PMC 接了单才发现要改料，可以转回工程）。
  #
  # 清空接单状态 = 接收人那边重新出现「待我接单」，超时计时也以本阶段 entered_at 为准
  # 不重置——否则来回转一次就能把超时重新洗白。
  def handoff_stage!(actor:, to_user:, note: nil)
    raise StandardError, '当前阶段无需接单，无法转交' unless STAGE_BOARD_KEYS.key?(stage)

    owners = current_stage_owner_ids
    raise StandardError, '只有本阶段负责人可以转交' unless owners.include?(actor.id)
    raise StandardError, '只能转给本阶段的另一位负责人' unless owners.include?(to_user.id)
    raise StandardError, '不能转给自己' if actor.id == to_user.id

    now = Time.current
    text = note.to_s.strip
    transaction do
      update!(stage_ack_at: nil, stage_ack_by_id: nil)
      stage_events.where(stage: stage).update_all(acked_at: nil, acked_by_id: nil, updated_at: now)
      stage_ack_events.create!(account: account, stage: stage, kind: Mes::StageAckEvent::HANDOFF,
                               actor: actor, to_user: to_user, note: text.presence, happened_at: now)
    end
    Mes::Notifier.notify(
      account: account, recipients: [to_user.id], kind: 'stage_assigned',
      title: "待你接单：#{order_no}（#{STAGE_LABELS[stage]}）",
      body: "#{actor.name} 把 #{order_no}（#{product_name}）转给你处理#{text.present? ? "：#{text}" : '。'}",
      order: self
    )
    self
  end

  # 拒收打回：退回上一阶段并记原因；上一阶段重新计时、需重新接单，责任明确回上游。
  def reject_to_previous!(actor:, reason:)
    # 外购订单按短版脊柱(OUTSOURCE_STAGES)算上一阶段，避免退回到它根本不存在的自制阶段(如 PRODUCTION)而卡死。
    spine = is_outsourced ? OUTSOURCE_STAGES : STAGES
    idx = spine.index(stage)
    raise StandardError, '已是初始阶段，无法退回' if idx.nil? || idx.zero?

    prev = spine[idx - 1]
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

    # 不覆盖 manager_id（提交时已解析为应审批的部门主管），仅记审批时间/意见，保留留痕；
    # 管理员代批经控制器 admin 判定放行，无需借 manager_id 授权。
    update!(approval_status: 'MANAGER_APPROVED',
            manager_acted_at: Time.current, manager_comment: comment)
    Mes::Notifier.resolve(account: account, order: self, kinds: 'approval_pending')
    notify_approval_pending
    self
  end

  # 总经理通过 → 正式生效（is_draft 随之转 false，进入生产流转、下游可见）。
  def gm_approve!(actor, comment: nil)
    raise StandardError, '非「待总经理」环节' unless approval_status == 'MANAGER_APPROVED'

    update!(approval_status: 'APPROVED', gm_id: actor.id,
            gm_acted_at: Time.current, gm_comment: comment)
    Mes::Notifier.resolve(account: account, order: self, kinds: 'approval_pending')
    # 不发「审批通过」知会：收件人收到也无事可做，只会把真正要处理的待办挤下去。
    # 过没过看订单列表的状态就行。驳回仍然要发——那是要人回去改的。
    activate_stage_ack!
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
    Mes::Notifier.resolve(account: account, order: self, kinds: 'approval_pending')
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'approval_rejected',
      title: "审批被驳回：生产订单 #{order_no}",
      body: "驳回原因：#{reason}", order: self
    )
    self
  end

  # 确保本订单关联了商品编码（成品 SKU）：建单时「商品编码」选填，成品出入库(完工入库/出库)
  # 又必须按 crm_product_id 记库存，否则无编码成品会串到同一个 NULL 桶。此处兜底：
  # 已有则直接返回；否则按成品名在产品档案里找同名成品，找不到就按成品名建一条 FINISHED 成品并回写。
  # 返回 crm_product_id（成品名为空时返回 nil）。
  # 按成品名把生产订单挂到已有的产品档案上；**绝不自动建档**。
  #
  # 原先找不到就自动建一条，SKU 直接用中文品名——出来的是个假编码。
  # 后果是实打实的错账：同一个产品，手工建的单用假编码、采购入库用真编码（C.BB.320.007），
  # 在结存表里是**两个桶**，领料/出库照样说库存不足；期初库存按真编码导的也对不上；
  # 存货科目映射按 category 走，自动建的一律 FINISHED，分不进正确科目。
  # 现在关联不上就返回 nil，由调用方拦下来让人去补档案——宁可当场报错，不要静默造假数据。
  def link_crm_product_by_name!
    return crm_product_id if crm_product_id.present?

    pname = product_name.to_s.strip
    return nil if pname.blank?

    product = account.crm_products.where('LOWER(name) = ?', pname.downcase).order(:id).first
    return nil if product.nil?

    update_columns(crm_product_id: product.id, updated_at: Time.current)
    product.id
  end

  private

  # 数量文案：去掉多余小数（50.0 → 50）。
  def fnum(value)
    format('%g', value.to_f)
  end

  # 单行用料需求（用量按本单产量/基准产量放大）。
  def requirement_row(item, factor, product_map = {}, stock_map = {}, ordered_map = {})
    pid = product_map[item.material_no]
    ordered = pid ? (ordered_map[pid] || 0).to_d : 0.to_d
    {
      mes_material_id: item.mes_material_id,
      crm_product_id: pid,
      mes_supplier_id: item.mes_material&.default_supplier_id,
      material_no: item.material_no,
      material_name: item.material_name,
      specification: item.specification,
      unit: item.unit,
      category: item.category,
      # 辅助属性：供应商按「料号 + 辅助属性」才认得出要哪一种，算料时就带给采购。
      aux_attribute_name: item.aux_attribute_name,
      # 工程写给采购的注意事项（指定品牌/能否替代/到货节点），只在系统里给采购看。
      purchase_note: item.purchase_note,
      qty: (item.qty.to_d * factor),
      # 对应物料实时库存（跨仓合计）+ 工程在 BOM 上给的建议采购量，供采购参考。
      on_hand: pid ? (stock_map[pid] || 0).to_d : 0.to_d,
      suggested_purchase_qty: item.suggested_purchase_qty,
      # 本单这个料已经下出去多少（前端据此把已下满的行默认收起来）
      ordered_qty: ordered
    }
  end

  # ── 站内通知埋点 ──

  # 进入需接单的下游阶段时通知该阶段负责人（BOM_READY 例外：其待办由挂 BOM 时另发）。
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

  # 审批生效：建单阶段的接单计时从「生效时刻」起算（审批期间是草稿不计时），
  # 清掉旧接单留痕并通知工程/PMC 负责人接单出 BOM。
  def activate_stage_ack!
    return unless stage == 'SALES_CONFIRMED'

    now = Time.current
    stage_events.where(stage: 'SALES_CONFIRMED')
                .update_all(entered_at: now, acked_at: nil, acked_by_id: nil, updated_at: now)
    update_columns(stage_ack_at: nil, stage_ack_by_id: nil)
    notify_stage_assigned(nil)
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
