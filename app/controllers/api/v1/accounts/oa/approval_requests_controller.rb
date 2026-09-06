class Api::V1::Accounts::Oa::ApprovalRequestsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_request, only: [:show, :update, :approve, :reject, :cancel]

  RESULTS_PER_PAGE = 20

  def index
    @requests = filtered_requests
                .includes(:template, :applicant)
                .order(created_at: :desc)
                .page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  # 待办角标：待我审批数量；approver_view=false 时前端隐藏「待我审批」入口。
  def counts
    render json: {
      todo: todo_scope.count,
      mine: Current.account.oa_approval_requests.applied_by(current_user.id).count,
      cc: cc_scope.count,
      done: done_scope.count,
      approver_view: approver_view?
    }
  end

  def show; end

  def create
    # 补卡单先过考勤组补卡规则（时限/每月上限）。
    if (error = reclock_rule_error)
      return render json: { error: error }, status: :unprocessable_entity
    end

    @request = build_request
    @request.files.attach(params[:files]) if params[:files].present?
    render :show
  rescue Oa::SubmitApprovalService::ApproverResolutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 申请人修改自己的审批单：仅「审批中且尚无人处理」时可改（改字段/所在部门 + 增删附件）。
  # 改后按最新表单/部门重新物化审批链（部门主管/条件分支可能随之变化）。
  def update
    return render json: { error: '只能修改自己发起的审批单' }, status: :forbidden unless @request.applicant_id == current_user.id

    # 补卡单改单同样复查补卡规则（时限/当月上限），排除本单自身计数，防改日期绕过上限。
    if (error = reclock_rule_error(template: @request.template, exclude_request_id: @request.id))
      return render json: { error: error }, status: :unprocessable_entity
    end

    # 锁本单 + 锁内复检可编辑：序列化「申请人改单重建审批链」与「审批人正在审批」的并发，
    # 杜绝审批人刚同意的瞬间被改单把审批链重置。
    @request.with_lock do
      unless editable_by_applicant?(@request)
        return render json: { error: '该审批单已被处理或已结束，无法修改，请撤回后重新发起' }, status: :unprocessable_entity
      end

      @request.update!(
        title: params[:title].presence || @request.title,
        department_id: params[:department_id].presence,
        form_data: form_data_param
      )
      purge_removed_files
      @request.files.attach(params[:files]) if params[:files].present?
      Oa::SubmitApprovalService.rebuild_steps(request: @request.reload)
    end
    render :show
  rescue Oa::SubmitApprovalService::ApproverResolutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def approve
    act('approved')
  end

  def reject
    act('rejected')
  end

  def cancel
    return head :unprocessable_entity unless @request.applicant_id == current_user.id

    # 锁内复检 pending：避免与审批人同意/驳回并发时，撤回把已流转的单据覆盖回撤销态。
    canceled = false
    @request.with_lock do
      next unless @request.pending?

      @request.update!(status: 'canceled')
      canceled = true
    end
    return head :unprocessable_entity unless canceled

    render :show
  end

  private

  def act(decision)
    Oa::ActOnApprovalService.new(
      request: @request, actor: current_user, decision: decision, comment: params[:comment]
    ).perform
    render :show
  rescue Oa::ActOnApprovalService::InvalidAction, Crm::AttendanceApprovalService::WriteError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reclock_rule_error(template: nil, exclude_request_id: nil)
    template ||= Current.account.oa_approval_templates.find(params[:template_id])
    return nil unless template.attendance_kind == 'reclock'

    date = Crm::AttendanceApprovalService.form_dates(template, form_data_param).first
    return '请填写补卡日期' if date.nil?

    Crm::AttendanceApprovalService.reclock_violation(Current.account, current_user.id, date, exclude_request_id: exclude_request_id)
  end

  def build_request
    template = Current.account.oa_approval_templates.find(params[:template_id])
    title = params[:title].presence || "#{current_user.name}的#{template.name}"
    Oa::SubmitApprovalService.new(
      account: Current.account, applicant: current_user, template: template,
      attributes: { form_data: form_data_param, title: title, department_id: params[:department_id].presence }
    ).perform
  end

  # form_data 可能是 JSON（普通提交）或 multipart 嵌套哈希（带附件提交）。
  def form_data_param
    raw = params[:form_data]
    return {} if raw.blank?

    raw.respond_to?(:permit) ? raw.permit!.to_h : raw
  end

  # 可编辑：审批中，且还没有任何审批人处理过（同意/驳回）——首个审批人一动，申请人就不能改了。
  def editable_by_applicant?(request)
    request.pending? && request.steps.where(status: %w[approved rejected]).none?
  end

  # 删除申请人在编辑时勾掉的既有附件（remove_file_ids 为附件 id 数组）。
  def purge_removed_files
    ids = Array(params[:remove_file_ids]).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    @request.files.where(id: ids).find_each(&:purge)
  end

  def fetch_request
    @request = visible_requests.find(params[:id])
  end

  # 可见：申请人本人、任一步骤审批人、或管理员。
  def visible_requests
    return Current.account.oa_approval_requests if Current.account_user.administrator?

    Current.account.oa_approval_requests
           .left_joins(:steps)
           .where(
             'oa_approval_requests.applicant_id = :uid OR oa_approval_steps.approver_id = :uid ' \
             'OR oa_approval_requests.cc_user_ids @> ARRAY[:uid]::bigint[]',
             uid: current_user.id
           )
           .distinct
  end

  def filtered_requests
    case params[:filter]
    when 'todo' then todo_scope
    when 'done' then done_scope
    when 'cc' then cc_scope
    else Current.account.oa_approval_requests.applied_by(current_user.id)
    end
  end

  # 抄送给我的：抄送名单包含我（提交时按模板快照）。
  def cc_scope
    Current.account.oa_approval_requests
           .where('cc_user_ids @> ARRAY[?]::bigint[]', current_user.id)
  end

  # 待我审批：单据审批中，且当前步骤审批人是我、待审。
  def todo_scope
    Current.account.oa_approval_requests.where(status: 'pending')
           .joins(:steps)
           .where(oa_approval_steps: { approver_id: current_user.id, status: 'pending' })
           .where('oa_approval_steps.position = oa_approval_requests.current_position')
           .distinct
  end

  # 我已审批：我处理过（同意/驳回）的单据。
  def done_scope
    Current.account.oa_approval_requests
           .joins(:steps)
           .where(oa_approval_steps: { approver_id: current_user.id })
           .where.not(oa_approval_steps: { status: %w[pending skipped] })
           .distinct
  end

  # 「待我审批」入口是否展示：管理角色天然是审批人；
  # 其他成员看是否被指定过——审批模板流程里点名，或已有分派到名下的审批步骤。
  def approver_view?
    au = Current.account_user
    return true if au.administrator? || au.crm_deputy_admin? || au.crm_manager?
    return true if Oa::ApprovalStep.exists?(account_id: Current.account.id, approver_id: current_user.id)

    Current.account.oa_approval_templates.any? do |template|
      template.flow.any? { |step| step['type'] == 'user' && step['user_id'].to_i == current_user.id }
    end
  end

  def check_authorization
    authorize(Oa::ApprovalRequest)
  end
end
