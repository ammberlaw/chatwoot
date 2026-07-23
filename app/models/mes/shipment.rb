# == Schema Information
#
# Table name: mes_shipments
#
#  id                  :bigint           not null, primary key
#  approved_at         :datetime
#  kind                :string           default("PRODUCTION"), not null
#  notified_at         :datetime
#  product_line        :string
#  reject_reason       :text
#  remark              :text
#  shipment_no         :string           not null
#  shipped_at          :datetime
#  status              :string           default("DRAFT"), not null
#  submitted_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_customer_id     :bigint
#  crm_sales_order_id  :bigint
#  manager_id          :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#  warehouse_id        :bigint
#
# Indexes
#
#  index_mes_shipments_on_account_and_product_line    (account_id,product_line)
#  index_mes_shipments_on_account_id                  (account_id)
#  index_mes_shipments_on_account_id_and_shipment_no  (account_id,shipment_no) UNIQUE
#  index_mes_shipments_on_crm_customer_id             (crm_customer_id)
#  index_mes_shipments_on_crm_sales_order_id          (crm_sales_order_id)
#  index_mes_shipments_on_manager_id                  (manager_id)
#  index_mes_shipments_on_owner_id                    (owner_id)
#  index_mes_shipments_on_production_order_id         (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_sales_order_id => crm_sales_orders.id) ON DELETE => nullify
#  fk_rails_...  (manager_id => users.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#
class Mes::Shipment < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  # PRODUCTION 出库：DRAFT → SHIPPED（生产流转，原样）。
  # STOCK 现货出库：PENDING_APPROVAL →(主管审核)→ APPROVED →(仓库)→ SHIPPED；驳回 REJECTED（业务员改后重提）。
  STATUSES = %w[DRAFT PENDING_APPROVAL APPROVED REJECTED SHIPPED CANCELLED].freeze
  KINDS = %w[PRODUCTION STOCK].freeze
  # 出库时销售订单可推进到 SHIPPED 的前置状态。
  SALES_ORDER_ADVANCEABLE = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT].freeze
  SHIPMENTS_BOARD_KEY = 'mes_shipments_index'

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true # 现货出库审核人（CRM 部门主管）
  has_many :shipment_items, class_name: 'Mes::ShipmentItem', dependent: :destroy, inverse_of: :shipment
  accepts_nested_attributes_for :shipment_items, allow_destroy: true
  has_many_attached :files

  validates :shipment_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }

  def self.document_number_prefix = 'DN'
  def self.document_number_column = :shipment_no

  def stock? = kind == 'STOCK'

  # 现货出库提交审核：解析业务员所属 CRM 部门主管并落库通知。无主管则直接进「待出库」推仓库。
  # 重提（REJECTED）沿用同一路径重走审核。
  def submit_for_approval!(_actor = nil)
    raise StandardError, '仅现货出库单需要审核' unless stock?
    raise StandardError, '当前状态无法提交审核' unless %w[DRAFT REJECTED].include?(status)

    self.manager_id = resolve_manager_id
    self.submitted_at = Time.current
    self.reject_reason = nil
    if manager_id.present?
      update!(status: 'PENDING_APPROVAL')
      notify_approval_pending
    else
      approve_without_manager!
    end
    self
  end

  # 主管审核通过 → 待出库，并推仓库（通知出库板块负责人备货执行）。
  def approve!(actor)
    raise StandardError, '非「待审核」环节' unless status == 'PENDING_APPROVAL'

    update!(status: 'APPROVED', manager_id: actor.id, approved_at: Time.current)
    notify_warehouse_ready
    self
  end

  # 主管驳回 → 退回业务员（可改后重提）。需填原因。
  def reject!(actor, reason:)
    raise StandardError, '非「待审核」环节' unless status == 'PENDING_APPROVAL'

    update!(status: 'REJECTED', manager_id: actor.id, reject_reason: reason)
    Mes::Notifier.notify(
      account: account, recipients: owner_id, kind: 'shipment_rejected',
      title: "现货出库被驳回：#{shipment_no}", body: "驳回原因：#{reason}"
    )
    self
  end

  # 通知出库（XMind 节点8）：仅打时间戳，供仓管/业务员据此备货。
  def notify!
    update!(notified_at: Time.current)
  end

  # 出库：开成品出库 StockEntry 扣成品库存（并把生产订单推进 SHIPPED），
  # 回写来源销售订单为「已出货」。现货出库须主管审核通过（APPROVED）后仓库方可出库。
  def ship!
    raise StandardError, '现货出库单需主管审核通过后才能出库' if stock? && status != 'APPROVED'
    raise StandardError, '单据已出库或已作废' unless stock? || status == 'DRAFT'

    ensure_stock_sufficient!

    transaction do
      ts = Time.current
      entry = account.mes_stock_entries.create!(
        purpose: 'SHIPMENT', production_order: production_order, from_warehouse_id: warehouse_id, owner_id: owner_id,
        stock_entry_items_attributes: shipment_items.map do |item|
          { item_type: 'PRODUCT', crm_product_id: item.crm_product_id, qty: item.qty, warehouse_id: warehouse_id }
        end
      )
      entry.post!
      update_columns(status: 'SHIPPED', shipped_at: ts, updated_at: ts)
      writeback_sales_order(ts)
    end
    self
  end

  private

  def product_line_source = production_order

  def writeback_sales_order(timestamp)
    return if crm_sales_order.nil?
    return unless SALES_ORDER_ADVANCEABLE.include?(crm_sales_order.status)

    crm_sales_order.update_columns(status: 'SHIPPED', updated_at: timestamp)
  end

  # 库存不足拦截：逐行校验成品仓结存 ≥ 出库量，不足报错列出缺口（正/现货出库均适用，杜绝负库存）。
  def ensure_stock_sufficient!
    shortages = shipment_items.filter_map do |item|
      balance = account.mes_stock_balances.find_by(
        item_type: 'PRODUCT', crm_product_id: item.crm_product_id, warehouse_id: warehouse_id
      )
      on_hand = balance&.qty.to_d
      next if on_hand >= item.qty.to_d

      "#{item.crm_product&.name || "成品##{item.crm_product_id}"}（现货 #{fnum(on_hand)}，需 #{fnum(item.qty)}）"
    end
    raise StandardError, "成品库存不足，无法出库：#{shortages.join('；')}" if shortages.any?
  end

  # 现货出库审核人=业务员所属（主）部门负责人；本人即负责人则向上找上级部门负责人。
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

  # 无部门主管时：跳过审核直接进「待出库」并推仓库。
  def approve_without_manager!
    update!(status: 'APPROVED', approved_at: Time.current)
    notify_warehouse_ready
  end

  def notify_approval_pending
    Mes::Notifier.notify(
      account: account, recipients: manager_id, kind: 'shipment_approval_pending',
      title: "待审核：现货出库 #{shipment_no}",
      body: "#{owner&.name || '业务员'} 提交了现货出库单，待你（部门主管）审核。"
    )
  end

  # 推仓库：通知出库板块负责人（仓管）备货执行。
  def notify_warehouse_ready
    recipients = account.mes_board_owners.find_by(board_key: SHIPMENTS_BOARD_KEY)&.manager_ids || []
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'shipment_approved',
      title: "待出库：现货出库 #{shipment_no}",
      body: "#{customer_label}现货出库单已审核通过，请仓库出库。"
    )
  end

  def customer_label
    name = crm_customer&.name
    name.present? ? "#{name} 的" : ''
  end

  # 数量文案：去掉多余小数（50.0 → 50）。
  def fnum(value)
    format('%g', value.to_f)
  end
end
