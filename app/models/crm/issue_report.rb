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
end
