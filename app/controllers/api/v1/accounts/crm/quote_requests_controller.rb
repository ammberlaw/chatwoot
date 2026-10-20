# 定制报价申请：业务员提交参数，直属主管（或被转交的人）填价格回来。
#
# 可见范围：自己提交的 + 该我报价的。管理员/副管看全部（要能盯住有没有单子卡住没人报）。
class Api::V1::Accounts::Crm::QuoteRequestsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_request, only: [:show, :update, :quote, :transfer, :cancel]

  RESULTS_PER_PAGE = 20

  def index
    scope = visible_scope
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.for_applicant(current_user.id) if params[:filter] == 'mine'
    # 待我报价只留待处理的——报完还挂在这儿，主管永远不知道自己清完没有。
    scope = scope.for_pricer(current_user.id).pending if params[:filter] == 'to_quote'
    # 我已报价按「实际报价人」算：单子转交过的话，报价的是接手那位，不是原报价人。
    scope = scope.where(quoted_by_id: current_user.id) if params[:filter] == 'quoted_by_me'
    @count = scope.count
    @requests = scope.includes(:template, :applicant, :pricer, :quoted_by, :crm_customer)
                     .order(created_at: :desc)
                     .page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  def show; end

  # 提交申请：报价人默认落到业务员的直属主管；取不到就先挂空，由管理员在列表里转交。
  def create
    template = Current.account.crm_quote_request_templates.find_by(id: params[:template_id])
    line = template&.product_line.presence || params[:product_line].presence
    return render json: { error: '请选择产品线' }, status: :unprocessable_entity if line.blank?

    @quote_request = Current.account.crm_quote_requests.new(request_params)
    @quote_request.assign_attributes(
      template: template, product_line: line, spec_template: params[:spec_template],
      applicant_id: current_user.id, pricer_id: default_pricer_id, status: 'PENDING'
    )
    @quote_request.files.attach(params[:files]) if params[:files].present?
    @quote_request.save!
    notify_pricer(@quote_request, '有新的定制报价待你处理')
    render :show
  end

  # 撤销后重新编辑再交：只有提交人（或管理员）能改，且只能改「已撤销」的单——
  # 还挂在报价人手上的单被改了他看不见，会照着旧参数报价。改完直接回到待报价并重新通知。
  def update
    return render json: { error: '只有提交人或管理员能修改' }, status: :forbidden unless own_or_admin?
    return render json: { error: '只有已撤销的申请能重新编辑；请先撤销' }, status: :unprocessable_entity unless @quote_request.status == 'CANCELLED'

    @quote_request.assign_attributes(request_params)
    apply_template_change
    @quote_request.files.attach(params[:files]) if params[:files].present?
    @quote_request.pricer_id ||= default_pricer_id
    @quote_request.status = 'PENDING'
    @quote_request.save!
    notify_pricer(@quote_request, '有一单定制报价重新提交了')
    render :show
  end

  # 报价：只有当前报价人和管理员能填。
  def quote
    return render json: { error: '这单不该你报价' }, status: :forbidden unless can_price?

    @quote_request.quote!(
      user: current_user,
      price_micros: micros(params[:price]),
      currency: params[:currency],
      valid_until: params[:valid_until],
      note: params[:note]
    )
    crm_notify(@quote_request.applicant_id,
               "你的定制报价 #{@quote_request.request_no}（#{@quote_request.title}）已报价：" \
               "#{@quote_request.quote_currency} #{@quote_request.quoted_price}",
               ref: request_ref(@quote_request,
                                "已报价 #{@quote_request.quote_currency} #{@quote_request.quoted_price}"))
    render :show
  end

  # 转交：主管报不了价时手动推给别人（比如总经理）。
  def transfer
    return render json: { error: '这单不该你转交' }, status: :forbidden unless can_price?

    target = Current.account.users.find_by(id: params[:to_user_id])
    return render json: { error: '请选择转交对象' }, status: :unprocessable_entity if target.nil?

    @quote_request.transfer!(from: current_user, to: target, reason: params[:reason])
    notify_pricer(@quote_request.reload, "#{current_user.name} 转给你一单定制报价")
    render :show
  end

  def cancel
    return render json: { error: '只有提交人或管理员能撤销' }, status: :forbidden unless own_or_admin?

    @quote_request.update!(status: 'CANCELLED')
    render :show
  end

  # 侧栏角标：待我报价的单数。口径与「待我报价」页签完全一致（pricer 是我 + 还没报价），
  # 不然角标显示 3、点进去只有 1，角标就没人信了。
  def pending_count
    render json: { count: Current.account.crm_quote_requests.for_pricer(current_user.id).pending.count }
  end

  # 业务员填表用的模板（只列启用的）。
  def templates
    render json: {
      payload: Current.account.crm_quote_request_templates.active.ordered.map do |t|
        { id: t.id, product_line: t.product_line, name: t.name, description: t.description,
          form_fields: t.form_fields }
      end
    }
  end

  private

  # 控制器名推不出模型（模型在 Crm:: 命名空间下），显式指定，与其它 CRM 控制器同款。
  def check_authorization
    authorize(Crm::QuoteRequest)
  end

  # 派单/转交时提醒报价人。没有指定报价人（取不到直属主管）时提醒管理员，
  # 否则单子会静静躺着没人管——这类「交到某人手上」的流程最怕无声失败。
  def notify_pricer(request, prefix)
    text = "#{prefix}：#{request.request_no} #{request.title}（#{request.applicant&.crm_display_name}）"
    ref = request_ref(request, "#{request.applicant&.crm_display_name} 提交 · 待报价")
    return crm_notify(request.pricer_id, text, ref: ref) if request.pricer_id.present?

    Current.account.administrators.each do |a|
      crm_notify(a.id, "#{text}｜该业务员没有配直属主管，请指派报价人", ref: ref)
    end
  end

  # 通知挂上这张定制报价单，点一下直接定位到它（见 Chat::NotifyService#notify）。
  def request_ref(request, subtitle)
    { type: 'quote_request', id: request.id, label: '定制报价',
      title: "#{request.request_no} #{request.title}", subtitle: subtitle }
  end

  def fetch_request
    @quote_request = visible_scope.find(params[:id])
  end

  def visible_scope
    scope = Current.account.crm_quote_requests
    return scope if admin_like?

    scope.where(applicant_id: current_user.id).or(scope.where(pricer_id: current_user.id))
  end

  def can_price?
    @quote_request.pricer_id == current_user.id || admin_like?
  end

  def admin_like?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin?
  end

  # 直属主管：优先按提交时选的部门取负责人，否则回落到主负部门/任一部门（与 OA 审批同口径）。
  def default_pricer_id
    dept_id = params[:department_id]
    return Current.account.org_departments.find_by(id: dept_id)&.leader_id if dept_id.present?

    membership = Current.account.org_memberships.find_by(user_id: current_user.id, is_primary: true) ||
                 Current.account.org_memberships.find_by(user_id: current_user.id)
    membership&.department&.leader_id
  end

  def own_or_admin?
    @quote_request.applicant_id == current_user.id || admin_like?
  end

  # 重新提交时可能换了产品线/模板：按新建那套口径重新落模板、规格与产品线（没传就维持原样）。
  def apply_template_change
    template = Current.account.crm_quote_request_templates.find_by(id: params[:template_id])
    # 二选一，不互相污染；都没给（或给了找不到的 id）就维持原样，别把已有的模板抹掉。
    if params[:spec_template].present?
      @quote_request.spec_template = params[:spec_template]
      @quote_request.template = nil
    elsif template
      @quote_request.template = template
      @quote_request.spec_template = nil
    end
    line = template&.product_line.presence || params[:product_line].presence
    @quote_request.product_line = line if line.present?
  end

  def micros(value)
    return nil if value.blank?

    (value.to_s.gsub(/[^0-9.\-]/, '').to_f * 1_000_000).round
  end

  def request_params
    params.permit(:title, :crm_customer_id, :quantity)
          .merge(form_data: params[:form_data].is_a?(String) ? JSON.parse(params[:form_data]) : (params[:form_data] || {}).permit!.to_h)
  end
end
