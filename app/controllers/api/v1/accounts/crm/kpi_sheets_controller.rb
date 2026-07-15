class Api::V1::Accounts::Crm::KpiSheetsController < Api::V1::Accounts::Crm::BaseController
  # 绩效审批链参与者可能不是 CRM 销售（人事/总经理）。放宽门禁：
  # CRM 成员（管理员/主管/业务员）或被指定的人事/总经理均可进。
  skip_before_action :ensure_crm_access
  before_action :ensure_kpi_access
  before_action :check_authorization
  before_action :fetch_sheet, only: [:show, :update, :destroy, :submit, :score, :hr_confirm, :gm_confirm]

  # 数据范围：超管/管理员/指定人事/总经理看全部；部门负责人看本部门（含下级）+ 自己；业务员只看自己。
  def index
    scope = Current.account.crm_kpi_sheets.includes(:owner, :sheet_items)
    scope = scope.where(owner_id: visible_sheet_owner_ids) unless all_sheets_visible?
    scope = scope.for_month(Date.parse(params[:month])) if params[:month].present?
    @sheets = scope.order(period_month: :desc, id: :desc)
  end

  def show; end

  # 保存完成值(员工)/得分(主管)。按行 id 更新。
  def update
    Array(params.dig(:sheet, :sheet_items)).each do |raw|
      item = @sheet.sheet_items.find_by(id: raw[:id])
      next unless item

      attrs = raw.permit(:actual_value, :score).to_h
      item.update!(attrs) if attrs.present?
    end
    @sheet.reload
    render 'show'
  end

  def destroy
    @sheet.destroy!
    head :ok
  end

  # ── 审批链（每步：上传本方电子签 + 状态流转）。守卫失败即渲染错误并中断 ──
  def submit
    return unless ensure_owner!
    return unless transition!('PENDING', 'SUBMITTED') do
      attach_signature(:employee_signature)
      @sheet.employee_signed_at = Time.current
    end

    render 'show'
  end

  def score
    return unless ensure_manager!
    return unless transition!('SUBMITTED', 'SCORED') do
      attach_signature(:manager_signature)
      @sheet.manager_id = current_user.id
      @sheet.manager_signed_at = Time.current
    end

    @sheet.recompute_payout!
    render 'show'
  end

  def hr_confirm
    return unless ensure_role!(:hr_owner_id)
    return unless transition!('SCORED', 'HR_CONFIRMED') do
      attach_signature(:hr_signature)
      @sheet.hr_id = current_user.id
      @sheet.hr_confirmed_at = Time.current
    end

    render 'show'
  end

  def gm_confirm
    return unless ensure_role!(:gm_owner_id)
    return unless transition!('HR_CONFIRMED', 'ARCHIVED') do
      attach_signature(:gm_signature)
      @sheet.gm_id = current_user.id
      @sheet.gm_confirmed_at = Time.current
    end

    render 'show'
  end

  private

  def fetch_sheet
    @sheet = Current.account.crm_kpi_sheets.includes(:sheet_items, :owner).find(params[:id])
  end

  def check_authorization
    authorize(Crm::KpiSheet)
  end

  # 考核表按角色可见性放行（管理员/被指定人事·总经理/或开关允许的主管·业务员）。
  def ensure_kpi_access
    return if Crm::PerformanceSetting.sheet_visible?(Current.account.crm_performance_setting, Current.account_user)

    render_error(I18n.t('errors.crm.no_access', default: '无权访问 CRM'), :forbidden)
  end

  def can_manage?
    Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin? || Current.account_user&.crm_manager?
  end

  # 全量可见：超管/管理员，以及被指定的人事/总经理（审批链需要）。
  def all_sheets_visible?
    Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin? ||
      [perf_setting&.hr_owner_id, perf_setting&.gm_owner_id].include?(current_user.id)
  end

  # 部门负责人=所辖部门（含下级）成员 + 自己；业务员/其他=仅自己。
  def visible_sheet_owner_ids
    return [current_user.id] unless Current.account_user&.crm_manager?

    led = Current.account.org_departments.where(leader_id: current_user.id).pluck(:id)
    return [current_user.id] if led.empty?

    dept_ids = Org::Department.subtree_ids(Current.account, led)
    (Current.account.org_memberships.where(department_id: dept_ids).pluck(:user_id) + [current_user.id]).uniq
  end

  def perf_setting
    @perf_setting ||= Crm::PerformanceSetting.for_account(Current.account)
  end

  # 状态匹配则执行 yield+流转并返回 true；否则渲染错误并返回 false。
  def transition!(from, to)
    unless @sheet.status == from
      render_error('状态不符', :unprocessable_entity)
      return false
    end

    yield
    @sheet.status = to
    @sheet.save!
    true
  end

  def attach_signature(field)
    @sheet.public_send(field).attach(params[:signature]) if params[:signature].present?
  end

  # 守卫：通过返回 true；失败渲染错误并返回 false。
  def ensure_owner!
    return true if @sheet.owner_id == current_user.id || Current.account_user&.administrator?

    render_error('仅本人可提交', :forbidden)
    false
  end

  def ensure_manager!
    return true if can_manage?

    render_error('仅主管/管理员可打分', :forbidden)
    false
  end

  # 指定审批人（人事/总经理）或系统管理员。
  def ensure_role!(field)
    designated = perf_setting.public_send(field)
    return true if current_user.id == designated || Current.account_user&.administrator?

    render_error('无权确认此步', :forbidden)
    false
  end

  def render_error(msg, status)
    render json: { error: msg }, status: status
  end
end
