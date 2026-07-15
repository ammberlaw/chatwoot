class Api::V1::Accounts::Crm::EmployeeCompsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_comp, only: [:show, :update, :destroy]

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

  def comp_params
    params.require(:comp).permit(:name, :monthly_salary_micros, :performance_ratio, :baseline_target_micros, :rank_note, :owner_id)
  end
end
