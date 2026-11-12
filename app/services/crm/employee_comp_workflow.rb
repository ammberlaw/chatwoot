class Crm::EmployeeCompWorkflow
  def initialize(account:, actor:)
    @account, @actor = account, actor
  end

  def save(attributes, previous: nil)
    result = nil
    @account.with_lock(requires_new: true) do
      if previous
        previous.lock!
        raise Crm::OffboardingService::Invalid, '只能编辑当前有效薪资，历史版本已保留' unless previous.active?
        attributes = previous.attributes.slice('name', 'owner_id', 'monthly_salary_micros', 'performance_ratio',
                                               'baseline_target_micros', 'rank_note').merge(attributes.stringify_keys)
        previous.update_columns(active: false)
      end
      result = @account.crm_employee_comps.create!(attributes.merge('active' => true, 'previous_comp_id' => previous&.id))
      if previous && result.effective_on < previous.effective_on
        raise Crm::OffboardingService::Invalid, '新薪资版本的生效日期不能早于原版本'
      end
      Crm::HrEvent.record!(account: @account, actor: @actor, kind: 'comp_version_created', user_id: result.owner_id,
                          payload: { comp_id: result.id, previous_comp_id: previous&.id, effective_on: result.effective_on })
    end
    result
  end
end
