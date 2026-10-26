# == Schema Information
#
# Table name: mes_notifications
#
#  id                  :bigint           not null, primary key
#  body                :text
#  kind                :string           not null
#  read_at             :datetime
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  production_order_id :bigint
#  recipient_id        :bigint           not null
#
# Indexes
#
#  idx_on_account_id_recipient_id_read_at_4123636370  (account_id,recipient_id,read_at)
#  index_mes_notifications_on_account_id              (account_id)
#  index_mes_notifications_on_production_order_id     (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#  fk_rails_...  (recipient_id => users.id) ON DELETE => cascade
#
# MES 站内通知（生产流转 / 审批 / 接单待办）。与 Chatwoot 会话通知体系相互独立，
# 只服务生产管理板块；持久化便于未读角标与历史，另经 ActionCable 实时下发。
class Mes::Notification < ApplicationRecord
  # 通知类型。前端据此上色/跳转。
  # approval_approved / po_approval_approved 不再产生新通知（通过了没人需要动手，
  # 只会把待办挤下去）——常量保留，历史记录还按它归类。
  KINDS = %w[
    approval_pending approval_approved approval_rejected
    bom_reconfirm bom_confirmed bom_revised purchase_release_pending stage_assigned stage_returned
    po_approval_pending po_approval_approved po_approval_rejected
    order_revised
    production_reported fg_count_pending
    shipment_approval_pending shipment_approved shipment_rejected shipment_notified
    document_returned
    forwarded
    sales_return_pending sales_return_resolved
    alert_digest
    erp_installment_due erp_payable_due erp_expense_paid
  ].freeze

  # ERP（财务）复用本表发通知，但它们不该混进 MES 的站内通知——
  # 生产端打开站内通知看到一屏「应付已逾期」，真正的待接单/待审批被挤下去了。
  # 两边按模块各看各的。
  ERP_KINDS = %w[erp_installment_due erp_payable_due erp_expense_paid].freeze

  belongs_to :account
  belongs_to :recipient, class_name: 'User'
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :title, presence: true

  # 待办类通知同时推手机（该不该推由 job 按 GROUP_BY_KIND 判，见 Mes::TodoPushJob）。
  after_create_commit -> { Mes::TodoPushJob.perform_later(id) }

  # 通知分类（页面三个 tab）。**必须与前端 `MesNotificationsIndex.vue` 的 `KIND_META[].group` 一致**，
  # 两边不一致会出现「tab 角标说 5 条、点进去 3 条」。这里是权威口径：过滤与计数都走后端，
  # 前端那份只用来上色/取标签。未列出的 kind 一律归 progress（同前端 kindMeta 的兜底）。
  GROUP_BY_KIND = {
    'approval_pending' => 'todo', 'bom_reconfirm' => 'todo', 'purchase_release_pending' => 'todo',
    'po_approval_pending' => 'todo', 'stage_assigned' => 'todo', 'production_reported' => 'todo',
    'fg_count_pending' => 'todo', 'shipment_approval_pending' => 'todo', 'shipment_approved' => 'todo',
    'erp_installment_due' => 'todo', 'erp_payable_due' => 'todo',
    'approval_rejected' => 'rejected', 'po_approval_rejected' => 'rejected', 'stage_returned' => 'rejected',
    'shipment_rejected' => 'rejected', 'document_returned' => 'rejected',
    # 退回给业务：业务那边是「有东西等你处理」进待办；退单人收到的确认回执是进度。
    'sales_return_pending' => 'todo',
    # 生产预警周报（Mes::DailyAlertJob）：是知会不是待办——它汇总的是「这些单该注意了」，
    # 不对应任何一个可点的动作，放进待办会让角标常年不归零。
    'alert_digest' => 'progress'
  }.freeze
  GROUPS = %w[todo progress rejected].freeze

  def self.kinds_in_group(group)
    GROUP_BY_KIND.select { |_k, g| g == group }.keys
  end

  scope :unread, -> { where(read_at: nil) }
  # progress = 「既不是待办也不是退回」的其余全部（含未登记在 GROUP_BY_KIND 里的新 kind），
  # 故用排除法，不能正列——漏登记一个 kind 就会让它在三个 tab 里都查不到。
  scope :in_group, lambda { |group|
    case group.to_s
    when 'todo', 'rejected' then where(kind: kinds_in_group(group.to_s))
    when 'progress' then where.not(kind: kinds_in_group('todo') + kinds_in_group('rejected'))
    else all
    end
  }
  scope :for_recipient, ->(uid) { where(recipient_id: uid) }
  # id 兜底：批量写入的通知 created_at 常常同一毫秒，只按时间排翻页会漏条/重条。
  scope :for_module, ->(mod) { mod.to_s == 'erp' ? where(kind: ERP_KINDS) : where.not(kind: ERP_KINDS) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def read? = read_at.present?
end
