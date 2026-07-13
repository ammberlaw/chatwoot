class Api::V1::Accounts::Oa::ApprovalRequestsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_request, only: [:show, :approve, :reject, :cancel]

  RESULTS_PER_PAGE = 20

  def index
    @requests = filtered_requests
                .includes(:template, :applicant)
                .order(created_at: :desc)
                .page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  # 待办角标：待我审批数量。
  def counts
    render json: { todo: todo_scope.count, mine: Current.account.oa_approval_requests.applied_by(current_user.id).count }
  end

  def show; end

  def create
    @request = build_request
    @request.files.attach(params[:files]) if params[:files].present?
    render :show
  end

  def approve
    act('approved')
  end

  def reject
    act('rejected')
  end

  def cancel
    return head :unprocessable_entity unless @request.applicant_id == current_user.id && @request.pending?

    @request.update!(status: 'canceled')
    render :show
  end

  private

  def act(decision)
    Oa::ActOnApprovalService.new(
      request: @request, actor: current_user, decision: decision, comment: params[:comment]
    ).perform
    render :show
  rescue Oa::ActOnApprovalService::InvalidAction => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  def fetch_request
    @request = visible_requests.find(params[:id])
  end

  # 可见：申请人本人、任一步骤审批人、或管理员。
  def visible_requests
    return Current.account.oa_approval_requests if Current.account_user.administrator?

    Current.account.oa_approval_requests
           .left_joins(:steps)
           .where('oa_approval_requests.applicant_id = :uid OR oa_approval_steps.approver_id = :uid', uid: current_user.id)
           .distinct
  end

  def filtered_requests
    case params[:filter]
    when 'todo' then todo_scope
    when 'done' then done_scope
    else Current.account.oa_approval_requests.applied_by(current_user.id)
    end
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

  def check_authorization
    authorize(Oa::ApprovalRequest)
  end
end
