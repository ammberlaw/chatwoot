# == Schema Information
#
# Table name: mes_purchase_orders
#
#  id                         :bigint           not null, primary key
#  approval_status            :string           default("DRAFT"), not null
#  delivery_date              :date
#  exception_note             :text
#  expected_date              :datetime
#  export_count               :integer          default(0), not null
#  extra_production_order_ids :bigint           default([]), not null, is an Array
#  follow_up_date             :datetime
#  gm_acted_at                :datetime
#  gm_comment                 :text
#  has_exception              :boolean          default(FALSE), not null
#  internal_remark            :text
#  last_exported_at           :datetime
#  po_no                      :string           not null
#  product_line               :string
#  remark                     :text
#  status                     :string           default("DRAFT"), not null
#  submitted_at               :datetime
#  total_amount_micros        :bigint
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  gm_id                      :bigint
#  owner_id                   :bigint
#  production_order_id        :bigint
#  purchase_requisition_id    :bigint
#
# Indexes
#
#  index_mes_purchase_orders_on_account_and_product_line        (account_id,product_line)
#  index_mes_purchase_orders_on_account_id                      (account_id)
#  index_mes_purchase_orders_on_account_id_and_approval_status  (account_id,approval_status)
#  index_mes_purchase_orders_on_account_id_and_po_no            (account_id,po_no) UNIQUE
#  index_mes_purchase_orders_on_account_id_and_status           (account_id,status)
#  index_mes_purchase_orders_on_extra_production_order_ids      (extra_production_order_ids) USING gin
#  index_mes_purchase_orders_on_gm_id                           (gm_id)
#  index_mes_purchase_orders_on_owner_id                        (owner_id)
#  index_mes_purchase_orders_on_production_order_id             (production_order_id)
#  index_mes_purchase_orders_on_purchase_requisition_id         (purchase_requisition_id)
#
# Foreign Keys
#
#  fk_rails_...  (gm_id => users.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (purchase_requisition_id => mes_purchase_requisitions.id) ON DELETE => nullify
#
class Mes::PurchaseOrder < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  require_product_line!
  include Mes::Returnable

  STATUSES = %w[DRAFT SUBMITTED PARTIAL_RECEIVED RECEIVED CANCELLED].freeze
  # 审批（总经理一级）：与收货状态 status 正交。DRAFT→提交→PENDING_GM（待总经理）→APPROVED/REJECTED。
  APPROVAL_STATUSES = %w[DRAFT PENDING_GM APPROVED REJECTED].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :purchase_requisition, class_name: 'Mes::PurchaseRequisition', optional: true # 由采购申请单转入（可空）
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :gm, class_name: 'User', optional: true # 审批总经理
  has_many :purchase_items, class_name: 'Mes::PurchaseItem', dependent: :destroy, inverse_of: :purchase_order
  accepts_nested_attributes_for :purchase_items, allow_destroy: true

  after_create :advance_production_order
  # 作废/删除已审批采购单时，把未收货部分的在途库存冲回，避免在途永久虚增。
  before_update :release_on_order_on_cancel
  before_destroy :release_on_order_if_open

  validates :po_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :approval_status, inclusion: { in: APPROVAL_STATUSES }

  scope :awaiting_gm_for, ->(uid) { where(approval_status: 'PENDING_GM', gm_id: uid) }

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
      elsif RECEIPT_DRIVEN_STATUSES.include?(status)
        # 收货量被冲回 0（入库单作废）时要退回「未到货」。
        # 原先这里写的是「保持原状」，结果作废后状态赖在 RECEIVED：单子显示已到货、
        # received? 还会让生产订单误判原料已齐套，而实际一件没收。
        'SUBMITTED'
      else
        status
      end
    update_column(:status, new_status) if new_status != status
  end

  # 由收货量驱动的状态：这几个才按 received_qty 重算，DRAFT 之类不受影响。
  RECEIPT_DRIVEN_STATUSES = %w[PARTIAL_RECEIVED RECEIVED].freeze

  def received? = status == 'RECEIVED'

  # 可删：还没进流程的草稿（未提审、未到货）。已提交/已批/已收过货的一律留痕，走「退回」而不是删。
  def deletable?
    status == 'DRAFT' && approval_status.in?(%w[DRAFT REJECTED]) &&
      purchase_items.where('received_qty > 0').none?
  end

  # 预览/导出计次：一个供应商几十张单时，采购员靠这个数一眼看出哪张还没导出转发过。
  # 原子自增，避免同一张单被连点两下只记一次。
  def record_export!
    self.class.where(id: id).update_all(['export_count = export_count + 1, last_exported_at = ?, updated_at = ?', Time.current, Time.current]) # rubocop:disable Rails/SkipsModelValidations
  end

  # 本单关联的全部生产订单 id（主单 + 额外关联的）。同款物料多张生产订单共用一次采购时，
  # 采购员在单上多挂几张，查询/追溯都认这一组。
  def all_production_order_ids
    ([production_order_id] + extra_production_order_ids.to_a).compact.uniq
  end

  def related_production_orders
    account.mes_production_orders.where(id: all_production_order_ids).order(:id)
  end

  # ── 审批链（总经理一级）──
  def pending_approval? = approval_status == 'PENDING_GM'
  def approved? = approval_status == 'APPROVED'
  def current_approver_id = pending_approval? ? gm_id : nil

  # 提交审批（草稿/被驳回可提交）：解析总经理、进「待总经理」，通知总经理。
  def submit_for_approval!(_actor = nil)
    raise StandardError, '当前状态无法提交审批' unless %w[DRAFT REJECTED].include?(approval_status)

    self.gm_id = resolve_gm_id
    # 未配置审批总经理时直接拒绝提交（否则单据进「待总经理」黑洞：无人可批、待办查不到、卡死）。
    raise StandardError, '未配置审批总经理（在绩效设置里指定），无法提交采购审批' if gm_id.blank?

    self.submitted_at = Time.current
    self.gm_acted_at = self.gm_comment = nil
    self.approval_status = 'PENDING_GM'
    save!
    notify_gm_pending
    self
  end

  # 总经理通过 → 生效，累加在途库存（已订购未到货）。
  def gm_approve!(actor, comment: nil)
    raise StandardError, '非「待总经理」环节' unless approval_status == 'PENDING_GM'

    transaction do
      update!(approval_status: 'APPROVED', gm_id: actor.id, gm_acted_at: Time.current, gm_comment: comment)
      apply_on_order!(1)
    end
    Mes::Notifier.resolve(account: account, kinds: 'po_approval_pending', title_like: po_no)
    # 同生产订单：通过了不发知会，省得把待办挤下去。驳回仍然发。
    self
  end

  # 总经理驳回 → 退回制单人。
  def reject_approval!(actor, reason:)
    raise StandardError, '当前状态无法驳回' unless pending_approval?

    update!(approval_status: 'REJECTED', gm_id: actor.id, gm_acted_at: Time.current, gm_comment: reason)
    Mes::Notifier.resolve(account: account, kinds: 'po_approval_pending', title_like: po_no)
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'po_approval_rejected',
      title: "采购单被驳回：#{po_no}", body: "驳回原因：#{reason}", order: production_order
    )
    self
  end

  # 作废/删除采购单时回冲在途：按每明细「未收货量(qty − received_qty)」冲减在途，避免在途永久虚增。
  def release_on_order!
    purchase_items.each do |it|
      outstanding = it.qty.to_d - it.received_qty.to_d
      next if outstanding <= 0

      reduce_on_order_for(
        item_type: it.item_type, mes_material_id: it.mes_material_id,
        crm_product_id: it.crm_product_id, qty: outstanding
      )
    end
  end

  # 在途库存增减（sign=+1 审批通过累加 / -1 到货冲减）：按明细的物料/成品累加到默认仓的 on_order。
  # 物料入原料仓、成品入成品仓；无对应仓则跳过（不阻塞审批）。
  def apply_on_order!(sign)
    purchase_items.each do |it|
      wh_id = default_warehouse_id_for(it)
      next if wh_id.nil?

      Mes::StockBalance.apply_on_order!(
        account_id: account_id, item_type: it.item_type, warehouse_id: wh_id,
        mes_material_id: it.mes_material_id, crm_product_id: it.crm_product_id,
        delta: sign * it.qty.to_d
      )
    end
  end

  # 到货冲减在途：按本次收货明细扣减 on_order（收多少冲多少，不为负）。
  def reduce_on_order_for(item_type:, mes_material_id:, crm_product_id:, qty:, warehouse_id: nil)
    wh_id = warehouse_id || default_warehouse_id_for_type(item_type)
    return if wh_id.nil?

    Mes::StockBalance.apply_on_order!(
      account_id: account_id, item_type: item_type, warehouse_id: wh_id,
      mes_material_id: mes_material_id, crm_product_id: crm_product_id, delta: -qty.to_d
    )
  end

  # ── 单据退回（Mes::Returnable）──：退回目标 = 工程/PMC BOM 板块。
  def document_board_key = 'mes_purchase_orders_index'
  def return_document_label = '采购单'
  def return_document_no = po_no
  # 已全部收货 / 已作废的采购单不可退回。
  def returnable? = %w[DRAFT SUBMITTED PARTIAL_RECEIVED].include?(status)

  private

  # 状态改为 CANCELLED（且原为已审批）→ 回冲未收货在途。
  def release_on_order_on_cancel
    release_on_order! if approved? && status_changed? && status == 'CANCELLED'
  end

  # 删除已审批且未作废的采购单 → 回冲未收货在途（防在途因硬删而虚增）。
  def release_on_order_if_open
    release_on_order! if approved? && status != 'CANCELLED'
  end

  def product_line_source = production_order

  # 总经理 = 绩效设置里的 gm_owner_id（与生产订单审批同一人）。
  def resolve_gm_id
    Crm::PerformanceSetting.for_account(account)&.gm_owner_id
  end

  # 提交后通知总经理审批（待办）。无总经理配置则不发（审批仍进 PENDING_GM，管理员可代批）。
  def notify_gm_pending
    return if gm_id.blank?

    Mes::Notifier.notify(
      account: account, recipients: gm_id, kind: 'po_approval_pending',
      title: "待审批采购单：#{po_no}",
      body: "#{owner&.name || '采购'} 提交了采购单 #{po_no}，请审批。", order: production_order
    )
  end

  # 明细默认仓：物料→原料仓(RAW)、成品→成品仓(FINISHED)。用于在途库存归仓。
  def default_warehouse_id_for(item)
    default_warehouse_id_for_type(item.item_type)
  end

  def default_warehouse_id_for_type(item_type)
    kind = item_type == 'PRODUCT' ? 'FINISHED' : 'RAW'
    account.mes_warehouses.find_by(kind: kind)&.id ||
      account.mes_warehouses.first&.id
  end

  # 建采购单即把关联生产订单从「工程BOM」推进到「采购原料」。
  def advance_production_order
    return if production_order.nil?
    return unless production_order.stage == 'BOM_READY'

    production_order.enter_stage!('PURCHASING', at: Time.current)
  end
end
