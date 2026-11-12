class Api::V1::Accounts::Oa::ApprovalRequestsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_request, only: [:show, :update, :destroy, :approve, :reject, :cancel, :revoke, :submit_draft, :resubmit, :remind, :transfer, :events, :transfer_candidates]

  RESULTS_PER_PAGE = 20

  def index
    @requests = filtered_requests
                .includes(:template, :applicant, :steps)
                .order(created_at: :desc)
                .page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  # 待办角标：待我审批数量；approver_view=false 时前端隐藏「待我审批」入口。
  def counts
    render json: {
      todo: todo_scope.count,
      mine: Current.account.oa_approval_requests.applied_by(current_user.id).where.not(status: 'draft').count,
      drafts: Current.account.oa_approval_requests.applied_by(current_user.id).where(status: 'draft').count,
      cc_unread: cc_scope.where.not(id: Oa::ApprovalCcReceipt.where(user_id: current_user.id).where.not(read_at: nil).select(:request_id)).count,
      cc: cc_scope.count,
      done: done_scope.count,
      approver_view: approver_view?
    }
  end

  rescue_from Oa::FormValidator::InvalidForm, Oa::SubmitApprovalService::ApproverResolutionError,
              Crm::AttendanceApprovalService::WriteError, Crm::AttendanceRevokeService::RevokeError do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    if @request.cc_user_ids.include?(current_user.id)
      receipt = @request.cc_receipts.create_or_find_by!(user_id: current_user.id)
      receipt.update!(read_at: Time.current) if receipt.read_at.nil?
    end
  end

  def create
    @request = build_request
    render :show
  end

  def destroy
    @request.with_lock do
      unless @request.status == 'draft' && @request.applicant_id == current_user.id
        raise Oa::FormValidator::InvalidForm, '只能删除自己的草稿，历史申请不能删除'
      end
      @request.destroy!
    end
    head :no_content
  end

  def update
    @request = Oa::EditApprovalService.new(request: @request, actor: current_user, attributes: edit_attributes).perform
    render :show
  end

  def submit_draft
    @request = Oa::EditApprovalService.new(request: @request, actor: current_user, attributes: edit_attributes, submit: true).perform
    render :show
  end

  def resubmit
    unless @request.applicant_id == current_user.id && %w[rejected canceled].include?(@request.status)
      return render json: { error: '只能对自己已驳回或撤回的单据修改重提' }, status: :forbidden
    end
    attrs = edit_attributes
    removed_ids = Array(attrs[:remove_file_ids]).map(&:to_i)
    raise ActiveRecord::RecordNotFound unless @request.files.where(id: removed_ids).count == removed_ids.uniq.size

    @request = Oa::SubmitApprovalService.new(account: Current.account, applicant: current_user, template: @request.template,
      attributes: attrs.merge(title: @request.title, source_request_id: @request.id, submission_key: params[:submission_key],
                              files: @request.files.reject { |file| removed_ids.include?(file.id) }.map(&:blob) + Array(attrs[:files]))).perform
    render :show
  end

  def remind
    collaboration.remind!
    render :show
  rescue Oa::ApprovalCollaboration::RateLimited => error
    render json: { error: error.message }, status: :too_many_requests
  end

  def transfer
    collaboration.transfer!(params[:user_id], params[:reason])
    render :show
  end

  def transfer_candidates
    raise Pundit::NotAuthorizedError unless collaboration.manager?
    ids = Current.account.account_users.active_members.where.not(user_id: @request.applicant_id).select(:user_id)
    render json: { payload: User.where(id: ids).map { |user| { id: user.id, name: user.crm_display_name } } }
  end

  def events
    render json: { payload: @request.events.includes(:actor, files_attachments: :blob).order(id: :desc).map { |event|
      { id: event.id, kind: event.kind, actor_name: event.actor&.crm_display_name, payload: event.payload,
        created_at: event.created_at, files: event.files.map { |file| { filename: file.filename.to_s, url: url_for(file) } } }
    } }
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
    canceled = approver_id = nil
    @request.with_lock do
      next unless @request.pending?

      approver_id = @request.current_step&.approver_id # 改成 canceled 后就问不出 current_step 了
      @request.update!(status: 'canceled')
      @request.event!('canceled', actor: current_user)
      canceled = true
    end
    return head :unprocessable_entity unless canceled

    Oa::ApprovalNotifier.new(@request).canceled(approver_id)
    render :show
  end

  # 销假：对已通过的考勤类单据发起撤销，本身是一张走审批的新单（原审批链），
  # 通过后才回滚考勤。只有申请人本人能发起，且只能销今天及以后的假。
  def revoke
    return render json: { error: '只能撤销自己发起的审批单' }, status: :forbidden unless @request.applicant_id == current_user.id
    return render json: { error: '该单据不可撤销（仅已通过的请假/外出单，且尚有未开始的日期）' }, status: :unprocessable_entity unless @request.revocable?

    requested = Crm::AttendanceApprovalService.form_dates(@request.definition, form_data_param)
    original = Crm::AttendanceApprovalService.form_dates(@request.definition, @request.form_data)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    unless requested.any? && original.any? && requested.min >= [today, original.min].max && requested.max <= original.max
      raise Oa::FormValidator::InvalidForm, '销假日期必须在原单今天及以后的区间内'
    end

    @request = Oa::SubmitApprovalService.revoke(
      original: @request, applicant: current_user, form_data: form_data_param, submission_key: params[:submission_key]
    )
    render :show
  rescue Oa::SubmitApprovalService::ApproverResolutionError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  def edit_attributes
    attrs = { form_data: form_data_param, files: params[:files], remove_file_ids: params[:remove_file_ids],
              template_revision: params[:template_revision] }
    attrs[:department_id] = params[:department_id] if params.key?(:department_id)
    attrs[:title] = params[:title] if params.key?(:title)
    attrs
  end

  def collaboration
    Oa::ApprovalCollaboration.new(request: @request, actor: current_user, account_user: Current.account_user)
  end

  def build_request
    template = Current.account.oa_approval_templates.find(params[:template_id])
    Oa::SubmitApprovalService.new(account: Current.account, applicant: current_user, template: template,
      attributes: edit_attributes.merge(title: params[:title], department_id: params[:department_id].presence,
                                         submission_key: params[:submission_key], draft: ActiveModel::Type::Boolean.new.cast(params[:draft]))).perform
  end

  # form_data 可能是 JSON（普通提交）或 multipart 嵌套哈希（带附件提交）。
  def form_data_param
    raw = params[:form_data]
    return {} if raw.blank?

    raw.respond_to?(:permit) ? raw.permit!.to_h : raw
  end

  def fetch_request
    @request = visible_requests.includes(:steps).find(params[:id])
  end

  # 可见：申请人本人、任一步骤审批人、或管理员。
  def visible_requests
    base = Current.account.oa_approval_requests.where.not(status: 'draft').or(Current.account.oa_approval_requests.where(status: 'draft', applicant_id: current_user.id))
    return base if Current.account_user.administrator?

    base.left_joins(:steps)
           .where(
             'oa_approval_requests.applicant_id = :uid OR oa_approval_steps.approver_id = :uid ' \
             'OR oa_approval_requests.cc_user_ids @> ARRAY[:uid]::bigint[]',
             uid: current_user.id
           )
           .distinct
  end

  def filtered_requests
    scope = case params[:filter]
            when 'todo' then todo_scope
            when 'done' then done_scope
            when 'cc' then cc_scope
            when 'drafts' then Current.account.oa_approval_requests.applied_by(current_user.id).where(status: 'draft')
            else Current.account.oa_approval_requests.applied_by(current_user.id).where.not(status: 'draft')
            end
    by_status(by_month(scope))
  end

  # 按状态筛。只认已知的四个值，别的（含空串）一律当没筛——
  # 前端传个拼错的状态不该静默返回空列表。
  def by_status(scope)
    status = params[:status].to_s.strip
    return scope unless Oa::ApprovalRequest::STATUSES.include?(status)

    scope.where(status: status)
  end

  # 按月筛（YYYY-MM）。一页 20 条、库里已经 100 张单，不按月筛就只能看见最新那 20 条——
  # 九月的 49 张一张都翻不到。口径用提交时间（created_at），和列表上显示的那个时间一致。
  def by_month(scope)
    month = params[:month].to_s.strip
    return scope unless month.match?(/\A\d{4}-\d{2}\z/)

    from = Date.strptime(month, '%Y-%m').beginning_of_month
    scope.where(created_at: from.beginning_of_day..from.end_of_month.end_of_day)
  rescue Date::Error
    scope
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
