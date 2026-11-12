# 提交审批：按模板 flow 物化成有序审批步骤并解析审批人，定位到首个可办步骤。
# 解析不到审批人或条件未命中时拒绝提交；只有明确配置免审批才能自动通过。
#
# flow 支持两类节点（有序）：
#   固定步骤：{ type: 'user'|'dept_leader', user_id? }
#   条件分支：{ type: 'condition', branches: [{ conditions: [{var, op, value}], flow: [步骤…] }, …] }
#     branches 自上而下取首个「全部条件命中」的分支（conditions 为空=默认兜底），展开其 flow 为步骤。
#     分支的 flow 里可以再放条件分支：先按发起人分组、组内再按天数分，按需递归展开。
#   条件变量 var：leave_days（按日期区间算的请假天数）/ field:<字段key>（表单值）/
#     department（申请人部门 id，单选等于）/ applicant（发起人属于，值是 ["dept:1","user:9"] 多选，op=in|not_in）。
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
    @revokes_request_id = attributes[:revokes_request_id]
    @attributes = attributes
    @definition = attributes[:definition] || Oa::TemplateSnapshot.new(template.snapshot)
  end

  # 发起销假：复用原单的模板与部门（同一套审批链与日期字段），form_data 只带销假区间。
  def self.revoke(original:, applicant:, form_data:, submission_key: nil)
    new(account: original.account, applicant: applicant, template: original.template,
        attributes: { form_data: original.form_data.merge(form_data), title: "销假：#{original.title}",
                      department_id: original.department_id, revokes_request_id: original.id, definition: original.definition, submission_key: submission_key }).perform
  end

  # 申请人修改审批单后按最新 form_data/部门重新物化审批链（审批中且尚无人处理时用）。
  def self.rebuild_steps(request:)
    new(account: request.account, applicant: request.applicant, template: request.template,
        attributes: { form_data: request.form_data, department_id: request.department_id }).rebuild(request)
  end

  def perform
    created = false
    request = nil
    membership = @account.account_users.active_members.find_by!(user_id: @applicant.id)
    membership.with_lock do
      key = @attributes[:submission_key].presence
      raise Oa::FormValidator::InvalidForm, '请求标识格式不正确' if key && (!key.is_a?(String) || key.length > 128)
      raise Oa::FormValidator::InvalidForm, '表单数据格式不正确' unless @form_data.nil? || @form_data.is_a?(Hash)
      digest = submission_digest
      request = @account.oa_approval_requests.find_by(applicant_id: @applicant.id, submission_key: key) if key
      if request
        original = request.events.order(:id).first&.payload&.dig('submission_digest')
        raise Oa::FormValidator::InvalidForm, '该请求已提交，请查看原单或重新发起申请' unless original == digest
      end
      unless request
        @template.with_lock do
          raise Oa::FormValidator::InvalidForm, '该审批模板已停用' unless @template.active? || @revokes_request_id
          if @attributes[:template_revision].present? && @template.revision != @attributes[:template_revision].to_i
            raise Oa::FormValidator::InvalidForm, '模板已更新，请重新打开并核对后提交'
          end
          @definition = Oa::TemplateSnapshot.new(@template.snapshot) unless @attributes[:definition]
          validate_submission!
          draft = @attributes[:draft] == true
          request = @account.oa_approval_requests.create!(template: @template, applicant: @applicant,
            title: @title.presence || "#{@applicant.name}的#{@definition.name}", department_id: @department_id,
            department_name_snapshot: @account.org_departments.find_by(id: @department_id)&.name,
            revokes_request_id: @revokes_request_id, source_request_id: @attributes[:source_request_id],
            template_snapshot: @definition.data, form_data: @form_data || {}, submission_key: key,
            status: draft ? 'draft' : 'pending', current_position: 0, submitted_at: draft ? nil : Time.current,
            cc_user_ids: draft ? [] : Array(@definition.cc_user_ids).map(&:to_i).uniq)
          request.files.attach(@attributes[:files]) if @attributes[:files].present?
          unless draft
            build_steps(request)
            settle_start(request)
          end
          request.event!(draft ? 'draft_saved' : (@attributes[:source_request_id] ? 'resubmitted' : 'submitted'), actor: @applicant,
                         payload: { 'source_request_id' => @attributes[:source_request_id], 'template_revision' => @definition.revision, 'submission_digest' => digest })
          created = true
        end
      end
    end
    if created && request.status != 'draft'
      request.pending? ? Oa::ApprovalNotifier.new(request).submitted : Oa::ApprovalNotifier.new(request).acted
    end
    request
  end

  def validate_submission!
    Oa::FormValidator.new(account: @account, applicant: @applicant, definition: @definition, form_data: @form_data || {},
                         department_id: @department_id, partial: @attributes[:draft] == true, revoke: @revokes_request_id.present?).validate!
    return if @attributes[:draft] || @revokes_request_id

    overlap = Crm::AttendanceApprovalService.overlap_violation(@account, @applicant.id, @definition, @form_data || {})
    raise Oa::FormValidator::InvalidForm, overlap if overlap
    if @definition.attendance_kind == 'reclock'
      date = Crm::AttendanceApprovalService.form_dates(@definition, @form_data || {}).first
      raise Oa::FormValidator::InvalidForm, '请填写补卡日期' unless date
      error = Crm::AttendanceApprovalService.reclock_violation(@account, @applicant.id, date)
      raise Oa::FormValidator::InvalidForm, error if error
    end
  end

  # 重建审批链：清掉旧步骤，按当前 flow/部门/条件重新展开并定位首个可办步骤。
  def rebuild(request)
    @definition = request.definition
    ApplicationRecord.transaction do
      request.steps.destroy_all
      build_steps(request)
      settle_start(request)
    end
    request
  end

  private

  def submission_digest
    files = Array(@attributes[:files]).map do |file|
      unless file.is_a?(ActiveStorage::Blob) || file.is_a?(ActionDispatch::Http::UploadedFile)
        raise Oa::FormValidator::InvalidForm, '附件格式不正确'
      end
      if file.is_a?(ActiveStorage::Blob)
        [file.filename.to_s, file.byte_size, file.checksum]
      else
        [file.original_filename, file.size, Digest::MD5.file(file.tempfile.path).base64digest]
      end
    end
    payload = [@template.id, @title.to_s, @department_id.to_s, @revokes_request_id, @attributes[:source_request_id], @attributes[:draft] == true,
               (@form_data || {}).deep_stringify_keys.sort.to_h, files.sort]
    Digest::SHA256.hexdigest(JSON.generate(payload))
  end

  def build_steps(request)
    expand_flow(Array(@definition.flow)).each_with_index do |step, index|
      approver_id = resolve_approver(step)
      request.steps.create!(
        account_id: @account.id, position: index, approver_id: approver_id,
        status: 'pending'
      )
    end
  end

  # 把含条件分支的 flow 展开成一串固定步骤（条件按 form_data 求值、取首个命中分支）。
  # 命中分支的 flow 再递归展开——分支里还能套分支（发起人分组→组内按天数分）。
  def expand_flow(flow)
    Array(flow).flat_map do |entry|
      e = entry.with_indifferent_access
      next [e] unless e[:type] == 'condition'

      branch = pick_branch(e[:branches])
      raise ApproverResolutionError, '没有匹配的审批条件，请联系管理员补充默认分支' unless branch

      branch = branch.with_indifferent_access
      if Array(branch[:flow]).empty?
        raise ApproverResolutionError, '该条件分支未配置审批人或明确免审批' unless branch[:auto_approve] == true
        []
      else
        expand_flow(Array(branch[:flow]))
      end
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
    return match_applicant?(cond) if cond[:var].to_s == 'applicant'

    compare(cond[:op], condition_value(cond[:var]), cond[:value])
  end

  def compare(operator, actual, expected)
    case operator
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

  # 发起人属于：选中的成员里有本人，或本人所在部门落在选中部门（含其下级部门）里。
  # value 形如 ["dept:3", "user:17"]，部门与具体的人混选；op=not_in 时取反。
  def match_applicant?(cond)
    hit = applicant_among?(Array(cond[:value]))
    cond[:op].to_s == 'not_in' ? !hit : hit
  end

  def applicant_among?(tokens)
    user_ids = []
    dept_ids = []
    tokens.each do |token|
      kind, raw = token.to_s.split(':', 2)
      user_ids << raw.to_i if kind == 'user'
      dept_ids << raw.to_i if kind == 'dept'
    end
    return true if user_ids.include?(@applicant.id)
    return false if dept_ids.empty?

    applicant_department_ids.intersect?(Org::Department.subtree_ids(@account, dept_ids))
  end

  # 本人所在的全部部门（可能跨多个），再带上提交时所选部门。
  def applicant_department_ids
    @applicant_department_ids ||= begin
      ids = @account.org_memberships.where(user_id: @applicant.id).pluck(:department_id).compact
      ids << @department_id.to_i if @department_id.present?
      ids.uniq
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

  # 请假天数：日期字段最早/最晚为区间的自然日跨度（含首尾）；单日且时长不超过半个工作日=0.5。
  # 半天口径统一由 AttendanceApprovalService 判定，与通过时写考勤用的是同一套。
  def leave_days
    dates = Crm::AttendanceApprovalService.form_dates(@definition, @form_data || {})
    return 0 if dates.empty?

    span = (dates.max - dates.min).to_i + 1
    span == 1 && half_day_selected? ? 0.5 : span
  end

  def half_day_selected?
    Crm::AttendanceApprovalService.half_day?(@account, @applicant.id, @definition, @form_data || {})
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
    # 任一必要步骤解析不到本账号在职审批人，整次提交回滚。
    unless id.present? && @account.account_users.active_members.exists?(user_id: id)
      raise ApproverResolutionError, '审批人未设置或已停用，请联系管理员修正或转交'
    end

    id.to_i
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
      first.update!(assigned_at: Time.current)
      request.update!(current_position: first.position)
    elsif request.steps.exists?
      # 有步骤却一个 pending 都没有 = 全 skipped(审批人全部解析失败)。绝不能静默「自动通过」——
      # 尤其请假/补卡通过后会写考勤。抛错让提交失败并提示配置问题。
      raise ApproverResolutionError, '审批流未找到有效审批人，请联系管理员检查该模板的审批人或部门负责人配置'
    else
      # 空流程(模板本就无审批节点)=无需审批，直接通过。
      raise ApproverResolutionError, '未配置审批流程，也未明确免审批' if Array(@definition.flow).empty? && !@definition.auto_approve
      Oa::FinalizeApprovalService.new(request: request, actor: @applicant).perform
    end
  end
end
