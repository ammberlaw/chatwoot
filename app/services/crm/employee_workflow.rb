class Crm::EmployeeWorkflow
  def initialize(employee:, actor:, attributes:, handover_mode: nil, target_user_id: nil)
    @employee, @actor, @attributes = employee, actor, attributes
    @mode, @target = handover_mode, target_user_id
  end

  def perform
    if @employee.persisted? && @attributes[:status] == 'RESIGNED' && @employee.user_id.present?
      Crm::OffboardingService.new(account: @employee.account, user_id: @employee.user_id, actor: @actor,
                                 mode: @mode, target_user_id: @target, employee: @employee, employee_attributes: @attributes).perform
      return @employee.reload
    end
    @employee.account.with_lock(requires_new: true) do
      @employee.lock! if @employee.persisted?
      before = @employee.attributes.slice('department_id', 'job_title', 'status', 'user_id')
      original_user = @employee.user_id
      creating = @employee.new_record?
      @employee.assign_attributes(@attributes)
      if !creating && original_user.present? && original_user != @employee.user_id
        raise Crm::OffboardingService::Invalid, '已关联账号不能直接换人；请先核对员工档案'
      end
      @employee.save!
      Org::PersonnelSync.from_employee(@employee)
      Crm::HrEvent.record!(account: @employee.account, employee: @employee, actor: @actor,
                          kind: creating ? 'employee_created' : 'employee_changed',
                          payload: { before: before, after: @employee.attributes.slice('department_id', 'job_title', 'status', 'user_id') })
    end
    @employee
  end
end
