# 用户在 AI 助手里提交的「这是不是 bug」问题单。
#
# 价值在 context 那一列——提交那一刻的完整现场（诊断结论、该谁动、通知发没发、
# 提交人的角色）。没有现场，一句「出不了货」和发微信截图没区别，修的人还得
# 从头考古一遍。
# == Schema Information
#
# Table name: crm_issue_reports
#
#  id             :bigint           not null, primary key
#  action_type    :string
#  body           :text             not null
#  context        :jsonb            not null
#  resolution     :text
#  resolved_at    :datetime
#  status         :string           default("new"), not null
#  subject_no     :string
#  subject_type   :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  reporter_id    :bigint           not null
#  resolved_by_id :bigint
#  subject_id     :bigint
#
# Indexes
#
#  index_crm_issue_reports_on_account_status_created       (account_id,status,created_at)
#  index_crm_issue_reports_on_reporter_id                  (reporter_id)
#  index_crm_issue_reports_on_subject_type_and_subject_id  (subject_type,subject_id)
#
class Crm::IssueReport < ApplicationRecord
  STATUSES = %w[new ack fixed wontfix].freeze

  belongs_to :account
  belongs_to :reporter, class_name: 'User'
  belongs_to :resolved_by, class_name: 'User', optional: true

  validates :body, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :open_ones, -> { where(status: %w[new ack]) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def reporter_name = context.dig('reporter', 'name').presence || reporter&.name

  # 提交那一刻的诊断现场，摘成四样：单据类型、当时状态、第一条阻碍、在等谁。
  # 站内通知和「问题反馈」页用的是同一份，别各写一套——两边一走偏，
  # 管理员在通知里看到的和点进去看到的就对不上了。
  def diagnosis_summary
    diag = context['diagnosis']
    return {} unless diag.is_a?(Hash)

    { doc_type: diag['doc_type'].presence, status_label: diag['status_label'].presence,
      blocker: first_blocker(diag), waiting: waiting_summary(diag['waiting_on']) }.compact
  end

  private

  # 出库诊断把 blockers 放顶层，其余三类放在 actions 里——两种都认。
  def first_blocker(diag)
    rows = Array(diag['blockers']).presence || Array(diag['actions']).flat_map { |a| Array(a['blockers']) }
    rows.first.is_a?(Hash) ? rows.first['text'].presence : nil
  end

  # notified=false 的意思是「系统压根没给该动手的人发过通知」——这比「在等谁」更要紧，
  # 单独标出来，不然看的人会以为对方收到了只是没动。
  def waiting_summary(waiting)
    return nil unless waiting.is_a?(Hash) && waiting['label'].present?

    notified = waiting['notified']
    { label: waiting['label'], names: Array(waiting['names']).compact_blank,
      notified: notified.is_a?(Hash) && notified['supported'] ? notified['count'].to_i.positive? : nil }
  end
end
