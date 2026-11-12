class Oa::DefinitionValidator
  def initialize(template)
    @template = template
  end

  def validate!
    fields = @template.form_fields
    raise Oa::FormValidator::InvalidForm, '表单字段配置不正确' unless fields.is_a?(Array)

    keys = fields.pluck('key')
    if keys.uniq.size != keys.size || fields.any? do |field|
      field['key'].blank? || field['label'].blank? || Oa::FormValidator::FIELD_TYPES.exclude?(field['type'])
    end
      raise Oa::FormValidator::InvalidForm, '字段名称、类型或编码重复，请检查表单'
    end
    if (@template.cash_kind.present? || @template.erp_expense) && fields.none? { |field| field['type'] == 'amount' }
      raise Oa::FormValidator::InvalidForm, '资金联动模板必须包含金额字段'
    end

    validate_flow!(@template.flow, allow_empty: @template.auto_approve)
    ids = Array(@template.cc_user_ids).map(&:to_i)
    valid = @template.account.account_users.active_members.where(user_id: ids).count
    raise Oa::FormValidator::InvalidForm, '抄送人必须是本账号在职成员' unless valid == ids.uniq.size
  end

  private

  def validate_flow!(nodes, allow_empty: false)
    raise Oa::FormValidator::InvalidForm, '请配置审批人，或明确勾选免审批' unless nodes.is_a?(Array) && (nodes.any? || allow_empty)
    raise Oa::FormValidator::InvalidForm, '免审批不能同时配置审批节点' if allow_empty && nodes.any?

    nodes.each do |node|
      case node['type']
      when 'user'
        raise Oa::FormValidator::InvalidForm, '指定审批人不存在或已停用' unless @template.account.account_users.active_members.exists?(user_id: node['user_id'])
      when 'dept_leader' then next
      when 'condition' then validate_branches!(node)
      else raise Oa::FormValidator::InvalidForm, '审批节点类型不正确'
      end
    end
  end

  def validate_condition_value!(condition)
    value = condition['value']
    case condition['var']
    when 'department'
      ids = Array(value).map(&:to_i).uniq
      raise Oa::FormValidator::InvalidForm, '条件部门不属于本账号' unless @template.account.org_departments.where(id: ids).count == ids.size
    when 'applicant'
      raise Oa::FormValidator::InvalidForm, '条件成员或部门无效' unless value.is_a?(Array) && value.all? { |token| valid_applicant_token?(token) }
    else
      return unless %w[lt lte gt gte].include?(condition['op'])
      raise Oa::FormValidator::InvalidForm, '数值条件必须填写有效数字' unless BigDecimal(value.to_s, exception: false)&.finite?
    end
  end

  def valid_applicant_token?(token)
    type, id = token.to_s.split(':', 2)
    return @template.account.org_departments.exists?(id: id) if type == 'dept'
    return @template.account.account_users.active_members.exists?(user_id: id) if type == 'user'

    false
  end

  def validate_branches!(node)
    branches = node['branches']
    raise Oa::FormValidator::InvalidForm, '条件节点至少需要一个分支' unless branches.is_a?(Array) && branches.any?

    branches.each do |branch|
      Array(branch['conditions']).each do |condition|
        var = condition['var'].to_s
        recognized = %w[leave_days department applicant].include?(var) || @template.form_fields.any? { |field| "field:#{field['key']}" == var }
        allowed = var == 'applicant' ? %w[in not_in] : %w[eq neq in lt lte gt gte]
        raise Oa::FormValidator::InvalidForm, '条件的字段、比较方式或取值不正确' unless recognized && allowed.include?(condition['op']) && condition['value'].present?

        validate_condition_value!(condition)
      end
      validate_flow!(branch['flow'], allow_empty: branch['auto_approve'] == true)
    end
  end
end
