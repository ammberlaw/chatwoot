class Crm::HrWorkbench
  def initialize(account)
    @account = account
  end

  def payload
    today = Date.current
    employees = @account.crm_employees.includes(:department).order(:employee_no).to_a
    probation = employees.filter_map do |employee|
      date = employee.probation_end_date
      row(employee, 'probation', date) if employee.status == 'PROBATION' && date && date <= today + 7
    end
    contracts = employees.filter_map do |employee|
      date = employee.contract_end_date
      row(employee, 'contract', date) if employee.status != 'RESIGNED' && date && date <= today + 1.month
    end
    incomplete = employees.filter_map do |employee|
      next if employee.status == 'RESIGNED'
      missing = []
      missing << '所在部门' unless employee.department_id
      missing << '入职日期' unless employee.hire_date
      missing << '合同到期日' unless employee.contract_end_date
      row(employee, 'incomplete', nil).merge(missing: missing) if missing.any?
    end
    latest_runs = Crm::OffboardingRun.where(account: @account).order(created_at: :desc, id: :desc).to_a.uniq(&:user_id)
    failures = latest_runs.reject { |run| run.status == 'completed' }.map do |run|
      { id: run.employee_id, run_id: run.id, name: run.employee&.name || run.summary['employee_name'],
        kind: 'handover', status: run.status, error: run.error_message, user_id: run.user_id,
        mode: run.mode, target_user_id: run.target_user_id }
    end
    known = failures.map { |row| row[:user_id] }
    active_ids = @account.account_users.active_members.pluck(:user_id)
    employees.each do |employee|
      next unless employee.status == 'RESIGNED' && active_ids.include?(employee.user_id) && known.exclude?(employee.user_id)
      failures << { id: employee.id, name: employee.name, employee_no: employee.employee_no, kind: 'handover',
                    user_id: employee.user_id, mode: 'pool', error: '档案已标离职，关联账号尚未停用，请核对后办理交接' }
    end
    { probation: probation, contracts: contracts, incomplete: incomplete, handovers: failures }
  end

  private

  def row(employee, kind, date)
    { id: employee.id, name: employee.name, employee_no: employee.employee_no,
      department_name: employee.department&.name, kind: kind, due_on: date }
  end
end
