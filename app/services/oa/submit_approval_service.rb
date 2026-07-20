# 提交审批：按模板 flow 物化成有序审批步骤并解析审批人，定位到首个可办步骤。
# 解析不到审批人的步骤标记 skipped；若开头即无可办步骤（全跳过/空流程），直接通过。
class Oa::SubmitApprovalService
  def initialize(account:, applicant:, template:, attributes:)
    @account = account
    @applicant = applicant
    @template = template
    @form_data = attributes[:form_data]
    @title = attributes[:title]
    @department_id = attributes[:department_id]
  end

  def perform
    request = @account.oa_approval_requests.create!(
      template: @template, applicant_id: @applicant.id, title: @title, department_id: @department_id,
      form_data: @form_data || {}, status: 'pending', current_position: 0, submitted_at: Time.current,
      cc_user_ids: Array(@template.cc_user_ids).map(&:to_i).uniq
    )
    build_steps(request)
    settle_start(request)
    request
  end

  private

  def build_steps(request)
    Array(@template.flow).each_with_index do |step, index|
      approver_id = resolve_approver(step.with_indifferent_access)
      request.steps.create!(
        account_id: @account.id, position: index, approver_id: approver_id,
        status: approver_id ? 'pending' : 'skipped'
      )
    end
  end

  def resolve_approver(step)
    case step[:type]
    when 'user' then step[:user_id]
    when 'dept_leader' then applicant_dept_leader_id
    end
  end

  # 优先按提交时所选部门取负责人；否则回落到主负部门/任一部门。
  def applicant_dept_leader_id
    return @account.org_departments.find_by(id: @department_id)&.leader_id if @department_id.present?

    membership = @account.org_memberships.find_by(user_id: @applicant.id, is_primary: true) ||
                 @account.org_memberships.find_by(user_id: @applicant.id)
    membership&.department&.leader_id
  end

  def settle_start(request)
    first = request.steps.where(status: 'pending').order(:position).first
    if first
      request.update!(current_position: first.position)
    else
      request.update!(status: 'approved')
    end
  end
end
