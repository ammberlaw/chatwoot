class Api::V1::Accounts::Crm::EmployeeCompsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :check_authorization
  before_action :ensure_sensitive_session
  before_action :fetch_comp, only: [:show, :update, :destroy]
  after_action :log_access, only: [:index, :show]

  def index
    @comps = Current.account.crm_employee_comps.includes(:owner).order(created_at: :desc)
  end

  def show; end

  def create
    @comp = Current.account.crm_employee_comps.create!(comp_params)
  end

  def update
    @comp.update!(comp_params)
  end

  def destroy
    @comp.destroy!
    head :ok
  end

  private

  def fetch_comp
    @comp = Current.account.crm_employee_comps.find(params[:id])
  end

  # 薪资敏感：整对象仅管理员可读写（policy 全 admin）。
  def check_authorization
    authorize(Crm::EmployeeComp)
  end

  # 敏感区闸口：需先通过二次密码验证（15 分钟内免验）。
  def ensure_sensitive_session
    return if Crm::SensitiveSession.active?(Current.account, current_user)

    render json: { error: '需要二次验证', code: 'sensitive_verification_required' }, status: :forbidden
  end

  def log_access
    Current.account.crm_access_logs.create!(
      user_id: current_user.id, resource_type: 'Crm::EmployeeComp',
      resource_id: @comp&.id, action: params[:action] == 'index' ? 'list' : 'view'
    )
  end

  def comp_params
    params.require(:comp).permit(:name, :monthly_salary_micros, :performance_ratio, :baseline_target_micros, :rank_note, :owner_id)
  end
end
