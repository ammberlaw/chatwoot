# OA 审批模板：定义一类审批（请假/报销/采购…）的表单字段与审批流。
# form_fields: [{ key, label, type, required, options? }]（type: text|textarea|number|date|amount|select）
# flow: [{ type: 'user'|'dept_leader', user_id? }]（有序审批步骤）
# == Schema Information
#
# Table name: oa_approval_templates
#
#  id              :bigint           not null, primary key
#  active          :boolean          default(TRUE), not null
#  attendance_kind :string
#  cash_kind       :string
#  cc_user_ids     :bigint           default([]), not null, is an Array
#  description     :string
#  erp_expense     :boolean          default(FALSE), not null
#  flow            :jsonb            not null
#  form_fields     :jsonb            not null
#  icon            :string           default("i-lucide-file-check")
#  name            :string           not null
#  position        :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_oa_approval_templates_on_account_id  (account_id)
#
class Oa::ApprovalTemplate < ApplicationRecord
  belongs_to :account
  has_many :requests, class_name: 'Oa::ApprovalRequest', foreign_key: :template_id,
                      inverse_of: :template, dependent: :destroy

  validates :name, presence: true
  # 考勤联动：leave 请假单 / reclock 补卡申请 / trip 出差单；空=不联动。
  validates :attendance_kind, inclusion: { in: %w[leave reclock trip] }, allow_blank: true
  # 备用金台账联动：advance 备用金申请（通过记存入）/ reimburse 费用报销（通过记支出）；空=不联动。
  validates :cash_kind, inclusion: { in: %w[advance reimburse] }, allow_blank: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
end
