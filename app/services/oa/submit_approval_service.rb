# 提交审批：按模板 flow 物化成有序审批步骤并解析审批人，定位到首个可办步骤。
# 解析不到审批人的步骤标记 skipped；若开头即无可办步骤（全跳过/空流程），直接通过。
#
# flow 支持两类节点（有序）：
#   固定步骤：{ type: 'user'|'dept_leader', user_id? }
#   条件分支：{ type: 'condition', branches: [{ conditions: [{var, op, value}], flow: [固定步骤…] }, …] }
#     branches 自上而下取首个「全部条件命中」的分支（conditions 为空=默认兜底），展开其 flow 为步骤。
#   条件变量 var：leave_days（按日期区间算的请假天数）/ department（申请人部门id）/ field:<字段key>（表单值）。
class Oa::SubmitApprovalService
  # 审批流物化后一个有效审批人都没有（部门没配负责人 / 指定审批人已离职失效）→ 抛此错，
  # 由控制器提示，绝不静默「自动通过」（尤其请假/补卡会误写考勤）。
  class ApproverResolutionError < StandardError; end

  def initialize(account:, applicant:, template:, attributes:)
    @account = account
    @applicant = applicant
    @template = template
    @form_data = attributes[:form_data]
    @title = attributes[:title]
    @department_id = attributes[:department_id]
  end

  # 申请人修改审批单后按最新 form_data/部门重新物化审批链（审批中且尚无人处理时用）。
  def self.rebuild_steps(request:)
    new(account: request.account, applicant: request.applicant, template: request.template,
        attributes: { form_data: request.form_data, department_id: request.department_id }).rebuild(request)
  end

  def perform
    # 物化+定位同一事务：settle_start 判定「无有效审批人」时抛错回滚，绝不留下半物化的孤儿单。
    ApplicationRecord.transaction do
      request = @account.oa_approval_requests.create!(
        template: @template, applicant_id: @applicant.id, title: @title, department_id: @department_id,
        form_data: @form_data || {}, status: 'pending', current_position: 0, submitted_at: Time.current,
        cc_user_ids: Array(@template.cc_user_ids).map(&:to_i).uniq
      )
      build_steps(request)
      settle_start(request)
      request
    end
  end

  # 重建审批链：清掉旧步骤，按当前 flow/部门/条件重新展开并定位首个可办步骤。
  def rebuild(request)
    ApplicationRecord.transaction do
      request.steps.destroy_all
      build_steps(request)
      settle_start(request)
      request
    end
  end

  private

  def build_steps(request)
    expand_flow(Array(@template.flow)).each_with_index do |step, index|
      approver_id = resolve_approver(step)
      request.steps.create!(
        account_id: @account.id, position: index, approver_id: approver_id,
        status: approver_id ? 'pending' : 'skipped'
      )
    end
  end

  # 把含条件分支的 flow 展开成一串固定步骤（条件按 form_data 求值、取首个命中分支）。
  def expand_flow(flow)
    Array(flow).flat_map do |entry|
      e = entry.with_indifferent_access
      next [e] unless e[:type] == 'condition'

      branch = pick_branch(e[:branches])
      branch ? Array(branch.with_indifferent_access[:flow]).map(&:with_indifferent_access) : []
    end
  end

  # 分支自上而下取首个「全部条件命中」的；conditions 为空即默认兜底分支。
  def pick_branch(branches)
    Array(branches).find do |b|
      conds = Array(b.with_indifferent_access[:conditions])
      conds.empty? || conds.all? { |c| match_condition?(c.with_indifferent_access) }
    end
  end

  def match_condition?(cond)
    actual = condition_value(cond[:var])
    expected = cond[:value]
    case cond[:op]
    when 'eq' then actual.to_s == expected.to_s
    when 'neq' then actual.to_s != expected.to_s
    when 'in' then Array(expected).map(&:to_s).include?(actual.to_s)
    when 'lt' then to_num(actual) < to_num(expected)
    when 'lte' then to_num(actual) <= to_num(expected)
    when 'gt' then to_num(actual) > to_num(expected)
    when 'gte' then to_num(actual) >= to_num(expected)
    else false
    end
  end

  def condition_value(var)
    case var.to_s
    when 'leave_days' then leave_days
    when 'department' then (@department_id || applicant_primary_department_id)
    else @form_data&.dig(var.to_s.sub(/\Afield:/, ''))
    end
  end

  # 数值比较用（非数字→0，不抛错）。金额/天数按 Float 比较足够。
  def to_num(value) = value.to_s.to_f

  # 请假天数：日期字段最早/最晚为区间的自然日跨度（含首尾）；单日+半天时段=0.5。
  def leave_days
    dates = Crm::AttendanceApprovalService.form_dates(@template, @form_data || {})
    return 0 if dates.empty?

    span = (dates.max - dates.min).to_i + 1
    span == 1 && half_day_selected? ? 0.5 : span
  end

  def half_day_selected?
    Array(@template.form_fields)
      .select { |f| Crm::AttendanceApprovalService::HALF_DAY_FIELD_TYPES.include?(f['type']) }
      .filter_map { |f| @form_data&.dig(f['key']) }
      .any? { |v| Crm::AttendanceApprovalService::HALF_DAY_VALUES.include?(v.to_s.strip) }
  end

  def applicant_primary_department_id
    membership = @account.org_memberships.find_by(user_id: @applicant.id, is_primary: true) ||
                 @account.org_memberships.find_by(user_id: @applicant.id)
    membership&.department_id
  end

  def resolve_approver(step)
    id = case step[:type]
         when 'user' then step[:user_id]
         when 'dept_leader' then applicant_dept_leader_id
         end
    # 审批人必须是本账号在职成员：指定审批人已离职/部门负责人已移除 → 视为无效(nil→该步 skipped)，
    # 由 settle_start 兜底判定，绝不把审批推给一个不存在的人。
    return nil if id.blank?

    @account.account_users.exists?(user_id: id) ? id.to_i : nil
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
    elsif request.steps.exists?
      # 有步骤却一个 pending 都没有 = 全 skipped(审批人全部解析失败)。绝不能静默「自动通过」——
      # 尤其请假/补卡通过后会写考勤。抛错让提交失败并提示配置问题。
      raise ApproverResolutionError, '审批流未找到有效审批人，请联系管理员检查该模板的审批人或部门负责人配置'
    else
      # 空流程(模板本就无审批节点)=无需审批，直接通过。
      request.update!(status: 'approved')
    end
  end
end
