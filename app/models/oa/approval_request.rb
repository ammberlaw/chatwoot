# OA 审批单：一次提交的审批实例。提交时按模板 flow 物化成有序 steps，逐级流转。
# status: pending 审批中 / approved 通过 / rejected 驳回 / canceled 撤回
# == Schema Information
#
# Table name: oa_approval_requests
#
#  id               :bigint           not null, primary key
#  current_position :integer          default(0), not null
#  form_data        :jsonb            not null
#  status           :string           default("pending"), not null
#  submitted_at     :datetime
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  applicant_id     :bigint           not null
#  template_id      :bigint           not null
#
class Oa::ApprovalRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected canceled].freeze

  belongs_to :account
  belongs_to :template, class_name: 'Oa::ApprovalTemplate'
  belongs_to :applicant, class_name: 'User'
  has_many :steps, -> { order(:position) }, class_name: 'Oa::ApprovalStep', dependent: :destroy, inverse_of: :request

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :applied_by, ->(user_id) { where(applicant_id: user_id) }

  # 当前待办步骤（审批中时指向 current_position）。
  def current_step
    steps.find_by(position: current_position)
  end

  def pending?
    status == 'pending'
  end
end
