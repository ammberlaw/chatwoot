# OA 审批步骤：审批单里的一级审批，记录审批人与其动作。
# status: pending 待审 / approved 同意 / rejected 驳回 / skipped 跳过（如部门主管解析不到）
# == Schema Information
#
# Table name: oa_approval_steps
#
#  id          :bigint           not null, primary key
#  acted_at    :datetime
#  comment     :text
#  position    :integer          not null
#  status      :string           default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  approver_id :bigint
#  request_id  :bigint           not null
#
class Oa::ApprovalStep < ApplicationRecord
  belongs_to :account
  belongs_to :request, class_name: 'Oa::ApprovalRequest', inverse_of: :steps
  belongs_to :approver, class_name: 'User', optional: true

  scope :pending_for, ->(user_id) { where(approver_id: user_id, status: 'pending') }
end
