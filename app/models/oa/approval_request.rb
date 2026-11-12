# OA 审批单：一次提交的审批实例。提交时按模板 flow 物化成有序 steps，逐级流转。
# status: pending 审批中 / approved 通过 / rejected 驳回 / canceled 撤回
# == Schema Information
#
# Table name: oa_approval_requests
#
#  id                 :bigint           not null, primary key
#  cc_user_ids        :bigint           default([]), not null, is an Array
#  current_position   :integer          default(0), not null
#  form_data          :jsonb            not null
#  status             :string           default("pending"), not null
#  submitted_at       :datetime
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  applicant_id       :bigint           not null
#  department_id      :bigint
#  revokes_request_id :bigint
#  template_id        :bigint           not null
#
# Indexes
#
#  idx_approval_revokes                                 (account_id,revokes_request_id)
#  index_oa_approval_requests_on_account_id             (account_id)
#  index_oa_approval_requests_on_account_id_and_status  (account_id,status)
#  index_oa_approval_requests_on_applicant_id           (applicant_id)
#  index_oa_approval_requests_on_cc_user_ids            (cc_user_ids) USING gin
#  index_oa_approval_requests_on_department_id          (department_id)
#  index_oa_approval_requests_on_template_id            (template_id)
#
# Foreign Keys
#
#  fk_rails_...  (template_id => oa_approval_templates.id) ON DELETE => cascade
#
class Oa::ApprovalRequest < ApplicationRecord
  STATUSES = %w[draft pending approved rejected canceled].freeze

  belongs_to :account
  belongs_to :source_request, class_name: 'Oa::ApprovalRequest', optional: true
  has_many :resubmissions, class_name: 'Oa::ApprovalRequest', foreign_key: :source_request_id, dependent: :restrict_with_error, inverse_of: :source_request
  has_many :events, class_name: 'Oa::ApprovalEvent', foreign_key: :request_id, dependent: :destroy, inverse_of: :request
  has_many :cc_receipts, class_name: 'Oa::ApprovalCcReceipt', foreign_key: :request_id, dependent: :destroy, inverse_of: :request

  def definition
    Oa::TemplateSnapshot.new(template_snapshot.presence || template.snapshot(legacy: true))
  end

  def freeze_definition!
    update!(template_snapshot: template.snapshot(legacy: true)) if template_snapshot.blank?
  end

  def event!(kind, actor:, payload: {}, files: [])
    event = events.create!(account_id: account_id, kind: kind, actor: actor, payload: payload)
    event.files.attach(files) if files.any?
    event
  end

  def editable_by?(user_id)
    return false unless applicant_id == user_id
    return true if status == 'draft'

    pending? && steps.where(status: %w[approved rejected]).none? && !events.exists?(kind: 'transferred')
  end

  def overdue?
    return false unless pending?

    since = current_step&.assigned_at || submitted_at
    since.present? && since < definition.overdue_hours.to_i.clamp(1, 720).hours.ago
  end
  belongs_to :template, class_name: 'Oa::ApprovalTemplate'
  belongs_to :applicant, class_name: 'User'
  belongs_to :department, class_name: 'Org::Department', optional: true
  # 销假单指向被销的原单；原单反过来能查到销它的那些单。
  belongs_to :revokes_request, class_name: 'Oa::ApprovalRequest', optional: true
  has_many :revoke_requests, class_name: 'Oa::ApprovalRequest', foreign_key: :revokes_request_id,
                             dependent: :nullify, inverse_of: :revokes_request
  has_many :steps, -> { order(:position) }, class_name: 'Oa::ApprovalStep', dependent: :destroy, inverse_of: :request
  # ERP 报销打款引用本单。打过款就不许删——钱已付、出纳流水与凭证都产生了，
  # 删了单据它们会变成查不到来源的无主记录（DB 外键 restrict 是最后一道，这里给中文提示）。
  has_many :erp_expense_payouts, class_name: 'Erp::ExpensePayout', foreign_key: :oa_approval_request_id,
                                 dependent: :restrict_with_error, inverse_of: :approval_request
  has_many_attached :files

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :applied_by, ->(user_id) { where(applicant_id: user_id) }

  # 当前待办步骤（审批中时指向 current_position）。
  def current_step
    return steps.find { |step| step.position == current_position } if steps.loaded?

    steps.find_by(position: current_position)
  end

  def pending?
    status == 'pending'
  end

  def revoke_request? = revokes_request_id.present?

  # 能不能对这张单发起销假：已通过的考勤类单据，且还有「今天及以后」的假可销。
  # 财务类（付款/备用金/报销）不在此列——是否已打款牵扯 ERP，单独议。
  def revocable?
    return false unless status == 'approved'
    return false unless %w[leave trip].include?(definition.attendance_kind)
    return false if revoke_request?

    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    account.crm_attendance_records
           .where(approval_request_id: id, source: 'approval')
           .exists?(work_date: today..)
  end
end
