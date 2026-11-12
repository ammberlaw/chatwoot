class Org::PersonnelSync
  def self.from_employee(employee)
    return if employee.user_id.blank? || employee.status == 'RESIGNED'

    account = employee.account
    primary = account.org_memberships.find_by(user_id: employee.user_id, is_primary: true)
    if primary && primary.department_id != employee.department_id
      primary.skip_employee_sync = true
      primary.destroy!
    end
    return if employee.department_id.blank?

    membership = account.org_memberships.find_or_initialize_by(user_id: employee.user_id, department_id: employee.department_id)
    membership.skip_employee_sync = true
    membership.update!(is_primary: true, title: employee.job_title)
  end

  def self.from_membership(membership, removed: false)
    return if membership.skip_employee_sync
    return unless membership.is_primary? || membership.saved_change_to_is_primary? || removed

    account = membership.account
    employee = account.crm_employees.find_by(user_id: membership.user_id)
    return unless employee && employee.status != 'RESIGNED'

    primary = account.org_memberships.find_by(user_id: membership.user_id, is_primary: true)
    before = employee.attributes.slice('department_id', 'job_title')
    employee.update!(department_id: primary&.department_id, job_title: primary&.title)
    after = employee.attributes.slice('department_id', 'job_title')
    return if before == after

    Crm::HrEvent.record!(account: account, employee: employee, kind: 'employee_org_changed', payload: { before: before, after: after })
  end
end
