# 一次寄样：寄了什么、到哪了、客户怎么说。
#
# 轻量到刻意的程度——不走审批、不扣库存。业务员寄两台样机给客户试，
# 需要的只是「别忘了这事」和「客户回话了没」，不是一套出入库流程。
# 真要扣库存的批量出货走 Mes::Shipment，那条路已经有了。
# == Schema Information
#
# Table name: crm_samples
#
#  id                 :bigint           not null, primary key
#  carrier            :string
#  delivered_at       :datetime
#  feedback           :text
#  feedback_at        :datetime
#  feedback_result    :string
#  items              :jsonb            not null
#  recipient          :string
#  remark             :text
#  sent_at            :datetime
#  status             :string           default("PENDING"), not null
#  tracking_no        :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_customer_id    :bigint           not null
#  crm_opportunity_id :bigint
#  owner_id           :bigint
#
# Indexes
#
#  index_crm_samples_on_account_id_and_crm_customer_id  (account_id,crm_customer_id)
#  index_crm_samples_on_account_id_and_status           (account_id,status)
#  index_crm_samples_on_account_id_and_tracking_no      (account_id,tracking_no)
#  index_crm_samples_on_crm_opportunity_id              (crm_opportunity_id)
#  index_crm_samples_on_owner_id                        (owner_id)
#
class Crm::Sample < ApplicationRecord
  self.table_name = 'crm_samples'

  # 寄样的一生：待寄出 → 已寄出 → 已签收 → 已反馈。取消是旁路终态。
  # 「已签收」和「已反馈」分开：签收了不等于有回音，而真正要盯的恰恰是
  # 「东西到了、人没说话」那一段——那是最容易不了了之的地方。
  STATUSES = %w[PENDING SENT DELIVERED FEEDBACK CANCELLED].freeze
  STATUS_LABELS = { 'PENDING' => '待寄出', 'SENT' => '已寄出', 'DELIVERED' => '已签收',
                    'FEEDBACK' => '已反馈', 'CANCELLED' => '已取消' }.freeze

  # 客户试完的结论。NO_REPLY 单独列出来是因为它最常见，也最该被看见。
  FEEDBACK_RESULTS = %w[SATISFIED NEED_CHANGE REJECTED NO_REPLY].freeze
  FEEDBACK_LABELS = { 'SATISFIED' => '满意', 'NEED_CHANGE' => '要调整',
                      'REJECTED' => '不合适', 'NO_REPLY' => '没回音' }.freeze

  # 还没结束的：待寄出/已寄出/已签收。客户详情页默认先摆这些。
  OPEN_STATUSES = %w[PENDING SENT DELIVERED].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer'
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :owner, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :feedback_result, inclusion: { in: FEEDBACK_RESULTS }, allow_blank: true

  # 盖时间戳和推商机都放在模型回调里，**不放控制器**：放控制器的话，
  # 任何不走控制器的路径（脚本、agent 工具、后台任务）都悄悄失效——
  # 今天上午 create_customer 工具漏掉建联系人就是这么来的。
  before_validation :stamp_status_time
  after_commit :sync_opportunity_stage, on: [:create, :update]

  scope :open_ones, -> { where(status: OPEN_STATUSES) }
  scope :recent_first, -> { order(Arel.sql('COALESCE(sent_at, created_at) DESC'), id: :desc) }

  def status_label = STATUS_LABELS[status]
  def feedback_label = FEEDBACK_LABELS[feedback_result]

  # 寄出去多少天了。用来盯「东西早到了、客户一直没说话」那一批。
  def days_since_sent
    sent_at && ((Time.current - sent_at) / 86_400).floor
  end

  # 明细行的规范形态（jsonb 里键名可能不全，统一在这里收口）。
  def item_rows
    Array(items).filter_map do |item|
      next unless item.is_a?(Hash)

      { name: item['name'], model: item['model'], quantity: item['quantity'] }
    end
  end

  private

  # 状态推到哪一步，就把那一步的时间盖上。让人手填「什么时候寄的/什么时候到的」，
  # 十次有九次是空的——这个系统里所有要人额外填的字段都证明了这一点。
  # 已经有值的不覆盖：人改过的日期以人为准。
  STATUS_STAMPS = { 'SENT' => :sent_at, 'DELIVERED' => :delivered_at,
                    'FEEDBACK' => :feedback_at }.freeze

  def stamp_status_time
    column = STATUS_STAMPS[status]
    self[column] ||= Time.current if column
    # 状态还没推到「已反馈」但人已经把反馈写进去了，也算这一刻收到的。
    self.feedback_at ||= Time.current if feedback.present?
  end

  # 寄出去了＝这个商机进了「样品中」（见 Crm::OpportunityStageSync.from_sample）。
  # 失败只记日志：寄样本身已经存好了，不能因为商机没跟上就让保存失败。
  def sync_opportunity_stage
    Crm::OpportunityStageSync.from_sample(self)
  rescue StandardError => e
    Rails.logger.warn("[Crm::Sample] 推商机失败 sample=#{id}: #{e.class} #{e.message}")
  end
end
