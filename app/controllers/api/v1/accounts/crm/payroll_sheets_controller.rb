# 月度工资表：财务/人事核算。与员工薪资配置同一道安全规范——
# Pundit 鉴权 + 二次密码验证 + 访问留痕。全公司的钱都在这张表上。
class Api::V1::Accounts::Crm::PayrollSheetsController < Api::V1::Accounts::Crm::BaseController
  RESULTS_PER_PAGE = 20

  skip_before_action :ensure_crm_access
  before_action :check_authorization
  before_action :ensure_sensitive_session
  before_action :fetch_sheet, only: %i[show update destroy confirm reopen export]
  before_action :ensure_editable, only: %i[update destroy]
  after_action :log_access, only: %i[index show export]

  def index
    scope = Current.account.crm_payroll_sheets
    scope = scope.where(template: params[:template]) if params[:template].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    if params[:month].to_s.match?(/\A\d{4}-\d{2}\z/)
      m = Date.strptime(params[:month], '%Y-%m')
      scope = scope.where(period_month: m.beginning_of_month)
    end
    @sheets_count = scope.count
    @sheets = scope.ordered.page(params[:page] || 1).per(params[:per_page] || RESULTS_PER_PAGE)
  end

  def show
    @items = @sheet.items.ordered.includes(:user)
  end

  def create
    @sheet = Current.account.crm_payroll_sheets.create!(
      sheet_params.merge(created_by_id: current_user.id)
    )
    render :show
  end

  def update
    ActiveRecord::Base.transaction do
      @sheet.update!(sheet_params.except(:items))
      upsert_items(params[:sheet][:items]) if params[:sheet][:items].present?
    end
    @items = @sheet.items.ordered.includes(:user)
    render :show
  end

  def destroy
    @sheet.destroy!
    head :ok
  end

  # 导入：吃财务手上那张 Excel 的原格式，模板自动识别。
  def import
    file = params[:file]
    return render json: { error: '请选择文件' }, status: :unprocessable_entity if file.blank?

    sheet = Crm::PayrollImportService.new(
      account: Current.account, user: current_user, path: file.tempfile.path,
      period_month: params[:period_month].presence || Date.current,
      template: params[:template].presence, title: params[:title].presence
    ).import!
    render json: { id: sheet.id, count: sheet.items.count,
                   adjusted: sheet.items.where.not(adjustment_micros: 0).count }
  rescue Crm::PayrollImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 确认即封账：确认后不可改，要改先退回核算中。
  def confirm
    return render json: { error: '这张表已经确认过了' }, status: :unprocessable_entity if @sheet.confirmed?

    @sheet.update!(status: 'CONFIRMED', confirmed_by_id: current_user.id, confirmed_at: Time.current)
    @items = @sheet.items.ordered.includes(:user)
    render :show
  end

  def reopen
    @sheet.update!(status: 'DRAFT', confirmed_by_id: nil, confirmed_at: nil)
    @items = @sheet.items.ordered.includes(:user)
    render :show
  end

  private

  def fetch_sheet
    @sheet = Current.account.crm_payroll_sheets.find(params[:id])
  end

  # 确认后锁死：已确认的工资表是账，改了就和发出去的钱对不上。
  def ensure_editable
    return if @sheet.editable?

    render json: { error: '已确认的工资表不能修改，请先退回核算中' }, status: :unprocessable_entity
  end

  # 行级增改删。传了 id 的改，没传的新建，_destroy 的删。
  # 每次都重算——改了出勤天数或补贴，应发实发要跟着动。
  def upsert_items(rows)
    rows.each do |raw|
      attrs = raw.permit(ITEM_FIELDS + %i[id _destroy])
      if attrs[:id].present?
        item = @sheet.items.find(attrs[:id])
        next item.destroy! if attrs[:_destroy].to_s == 'true'

        item.update!(attrs.except(:id, :_destroy))
      else
        item = @sheet.items.new(attrs.except(:id, :_destroy).merge(account_id: Current.account.id))
      end
      item.compute!
      item.save!
    end
  end

  ITEM_FIELDS = %i[
    user_id employee_name position employment_status hire_date sort_order
    base_total_micros basic_salary_micros position_allowance_micros
    seniority_allowance_micros meal_allowance_micros lodging_allowance_micros
    attendance_bonus_micros excellent_bonus_micros performance_salary_micros
    commission_salary_micros
    weekday_ot_hours weekday_ot_rate_micros weekday_ot_pay_micros
    weekend_ot_hours weekend_ot_rate_micros weekend_ot_pay_micros
    actual_days expected_days leave_days
    late_deduction_micros absence_deduction_micros
    social_insurance_micros income_tax_micros
    adjustment_micros adjustment_reason remark
  ].freeze

  def sheet_params
    params.require(:sheet).permit(:period_month, :template, :title, :remark)
  end

  def check_authorization
    authorize(Crm::PayrollSheet)
  end

  def ensure_sensitive_session
    return if Crm::SensitiveSession.active?(Current.account, current_user)

    render json: { error: '需要二次验证', code: 'sensitive_verification_required' }, status: :forbidden
  end

  def log_access
    Current.account.crm_access_logs.create!(
      user_id: current_user.id, resource_type: 'Crm::PayrollSheet',
      resource_id: @sheet&.id, action: params[:action] == 'index' ? 'list' : 'view'
    )
  end
end
