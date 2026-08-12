class Api::V1::Accounts::Crm::EmployeesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :check_authorization
  before_action :ensure_sensitive_session
  before_action :fetch_employee, only: [:show, :update, :destroy, :attach, :detach, :audits]
  after_action :log_access, only: [:index, :show]

  # 员工数量有限，一次全量返回，分组/搜索由前端完成。
  def index
    @employees = Current.account.crm_employees.includes(:department).order(:employee_no)
  end

  def show; end

  def create
    @employee = Current.account.crm_employees.create!(employee_params)
  end

  # 状态从非离职改为「离职」且档案已关联系统账号时，自动执行离职交接：
  # 客户/商机按 handover_mode 退回公海（默认）或转移给 handover_target_id；个人文档进回收站；账号 CRM 角色置无。
  def update
    resigning = employee_params[:status] == 'RESIGNED' && @employee.status != 'RESIGNED'
    @employee.update!(employee_params)
    run_offboarding if resigning && @employee.user_id.present?
  end

  def destroy
    @employee.destroy!
    head :ok
  end

  # 操作历史：变更审计（audited）+ 查看记录（Crm::AccessLog）合并时间轴。
  def audits
    rows = (change_rows + view_rows).sort_by { |r| r[:created_at] }.last(80).reverse
    render json: { payload: rows }
  end

  # 附件上传：kind=photo（证件照，单张覆盖）/ entry（入职资料，追加）/ resign（离职资料，追加）。
  def attach
    files = Array(params[:files])
    case params[:kind]
    when 'photo' then @employee.photo.attach(files.first)
    when 'entry' then @employee.entry_files.attach(files)
    when 'resign' then @employee.resign_files.attach(files)
    end
    render 'api/v1/accounts/crm/employees/show'
  end

  # 删除单个附件（入职/离职资料或证件照，按附件 id 定位）。
  def detach
    ActiveStorage::Attachment.where(record: @employee).find(params[:attachment_id]).purge
    render 'api/v1/accounts/crm/employees/show'
  end

  private

  def fetch_employee
    @employee = Current.account.crm_employees.find(params[:id])
  end

  def change_rows
    @employee.audits.order(created_at: :desc).limit(60).map do |a|
      { kind: 'change', action: a.action, changed_fields: a.audited_changes.keys,
        user_name: a.user&.name || '系统', created_at: a.created_at }
    end
  end

  def view_rows
    Current.account.crm_access_logs
           .where(resource_type: 'Crm::Employee', resource_id: @employee.id, action: 'view')
           .order(created_at: :desc).limit(40).includes(:user)
           .map { |l| { kind: 'view', action: 'view', user_name: l.user.name, created_at: l.created_at } }
  end

  # 敏感区闸口：需先通过二次密码验证（15 分钟内免验）。
  def ensure_sensitive_session
    return if Crm::SensitiveSession.active?(Current.account, current_user)

    render json: { error: '需要二次验证', code: 'sensitive_verification_required' }, status: :forbidden
  end

  # 查看留痕：列表与单条查看都记录访问日志。
  def log_access
    Current.account.crm_access_logs.create!(
      user_id: current_user.id, resource_type: 'Crm::Employee',
      resource_id: @employee&.id, action: params[:action] == 'index' ? 'list' : 'view'
    )
  end

  def run_offboarding
    Crm::OffboardingService.new(
      account: Current.account,
      user_id: @employee.user_id,
      mode: params[:handover_mode].to_s,
      target_user_id: params[:handover_target_id].presence
    ).perform
  end

  # 含身份证/薪资/银行卡等敏感信息：整对象仅管理员可读写（policy 全 admin）。
  def check_authorization
    authorize(Crm::Employee)
  end

  def employee_params
    params.require(:employee).permit(
      :employee_no, :name, :gender, :id_card_no, :birth_date, :native_place, :user_id,
      :department_id, :job_title, :job_category, :work_location,
      :status, :hire_date, :regular_date, :probation_months,
      :contract_start_date, :contract_end_date, :contract_type, :renew_count,
      :salary_note, :bank_card_no, :bank_name,
      :phone, :email, :wechat,
      :resign_date, :resign_reason, :resign_type
    )
  end
end
