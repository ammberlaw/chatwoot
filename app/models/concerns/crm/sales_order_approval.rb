# 销售订单审核：审核通过才能转生产订单、才进财务「待建账」。
#
# 用户原话：「现在 crm 的销售订单转 mes 或 erp 时需要被审核才可以推送」。
# 审核人＝该订单业务员所在 CRM 团队的负责人（管理员/副管恒可审，见控制器 ensure_approver!）。
#
# 与 status（待确认/生产中/已出货…）**正交**：status 讲的是这单货走到哪了，
# approval_status 讲的是这单准不准往下游推。两件事混成一个字段的话，
# 「已出货但审核被驳回」这种状态就没法表达了。
#
# 建单即待审核，没有草稿/提交两步——单子开出来就是等主管看的那张，
# 多一次「提交」点击只会多一步没人记得做的操作（同原料入库审核那次的取舍）。
module Crm::SalesOrderApproval
  extend ActiveSupport::Concern

  APPROVAL_STATUSES = %w[PENDING APPROVED REJECTED].freeze
  APPROVAL_LABELS = { 'PENDING' => '待审核', 'APPROVED' => '已审核', 'REJECTED' => '已驳回' }.freeze

  included do
    belongs_to :approved_by, class_name: 'User', optional: true
    validates :approval_status, inclusion: { in: APPROVAL_STATUSES }
    scope :approved, -> { where(approval_status: 'APPROVED') }
    # 被驳回的单改完自动回待审核：驳回原因留着，主管能看出这单改过几轮。
    before_update :reopen_approval_on_edit
  end

  def approval_label = APPROVAL_LABELS[approval_status] || approval_status
  def approved? = approval_status == 'APPROVED'

  # 能不能往下游推（转生产订单 / 进财务待建账）。闸只认这一个判断，两边口径才不会走偏。
  def pushable? = approved?

  def approve!(actor)
    raise StandardError, '这张订单不在待审核状态' unless approval_status == 'PENDING'

    update!(approval_status: 'APPROVED', approved_by: actor, approved_at: Time.current, reject_reason: nil)
  end

  def reject!(actor, reason)
    raise StandardError, '这张订单不在待审核状态' unless approval_status == 'PENDING'
    raise StandardError, '请填写驳回原因' if reason.to_s.strip.blank?

    update!(approval_status: 'REJECTED', approved_by: actor, approved_at: Time.current,
            reject_reason: reason.to_s.strip)
  end

  private

  # 改单回待审核。只认业务字段的改动：审核动作自己、以及下游回写的状态/出货日期
  # 不该把单子打回重审（否则一出货就又变待审核，主管天天在批同一张单）。
  APPROVAL_NEUTRAL_FIELDS = %w[
    approval_status approved_by_id approved_at reject_reason
    status updated_at deleted_at deleted_by_id amount_includes_tax
  ].freeze

  def reopen_approval_on_edit
    return unless approval_status == 'REJECTED'
    return if (changed - APPROVAL_NEUTRAL_FIELDS).empty?

    self.approval_status = 'PENDING'
  end
end
