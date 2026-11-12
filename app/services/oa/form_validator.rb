class Oa::FormValidator
  class InvalidForm < StandardError; end
  DATE_TYPES = %w[date datetime].freeze
  FIELD_TYPES = %w[text textarea number amount date datetime select].freeze

  def initialize(account:, applicant:, definition:, form_data:, department_id:, partial: false, revoke: false)
    @account = account
    @applicant = applicant
    @definition = definition
    @data = form_data
    @department_id = department_id
    @partial = partial
    @revoke = revoke
  end

  def validate!
    raise InvalidForm, '表单数据格式不正确' unless @data.is_a?(Hash)

    validate_department!
    validate_values!
  end

  def validate_values!
    raise InvalidForm, '表单数据格式不正确' unless @data.is_a?(Hash)

    fields = Array(@definition.form_fields)
    unknown = @data.keys.map(&:to_s) - fields.pluck('key')
    raise InvalidForm, '表单字段已变化，请重新打开核对' if unknown.any?

    fields.each { |field| validate_field!(field) }
    if !@partial && !@revoke && (@definition.cash_kind.present? || @definition.erp_expense)
      amount = fields.find { |field| field['type'] == 'amount' }
      raise InvalidForm, '请填写有效金额' unless amount && @data[amount['key']].present?
    end
    validate_dates!(fields) unless @partial
    true
  end

  private

  def validate_department!
    if @department_id.present?
      department = @account.org_departments.find_by(id: @department_id)
      raise InvalidForm, '所选部门不存在或无权使用' unless department

      membership = @account.account_users.find_by!(user_id: @applicant.id)
      allowed = membership.administrator? || department.leader_id == @applicant.id ||
                @account.org_memberships.exists?(department_id: department.id, user_id: @applicant.id)
      raise InvalidForm, '只能使用本人所属或负责的部门' unless allowed
    elsif !@partial && needs_department?(Array(@definition.flow))
      raise InvalidForm, '请选择所在部门'
    end
  end

  def needs_department?(flow)
    flow.any? do |node|
      node['type'] == 'dept_leader' || (node['type'] == 'condition' && Array(node['branches']).any? do |branch|
        needs_department?(Array(branch['flow']))
      end)
    end
  end

  def validate_field!(field)
    key, type = field.values_at('key', 'type')
    value = @data[key]
    return if @revoke && DATE_TYPES.exclude?(type)

    if value.to_s.strip.empty?
      raise InvalidForm, "请填写#{field['label']}" if !@partial && field['required']

      return
    end
    raise InvalidForm, "#{field['label']}格式不正确" if value.is_a?(Hash) || value.is_a?(Array)

    case type
    when 'number', 'amount' then validate_number!(field, value)
    when 'date', 'datetime' then validate_date!(field, value)
    when 'select'
      raise InvalidForm, "#{field['label']}不在可选范围内" unless Array(field['options']).include?(value.to_s)
    end
  end

  def validate_number!(field, value)
    number = BigDecimal(value.to_s)
    raise ArgumentError unless number.finite?

    raise ArgumentError if (field['type'] == 'amount') && !(number.positive? && number <= BigDecimal('999999999999.99') && number.round(2) == number)
  rescue ArgumentError, TypeError
    raise InvalidForm, "#{field['label']}必须是#{field['type'] == 'amount' ? '大于零且最多两位小数的金额（不超过999999999999.99）' : '有效数字'}"
  end

  def validate_date!(field, value)
    if field['type'] == 'datetime' && !@revoke
      raise ArgumentError unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/)

      DateTime.iso8601(value.to_s)
    else
      raise ArgumentError unless value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value.to_s)
    end
  rescue ArgumentError
    raise InvalidForm, "#{field['label']}日期格式不正确"
  end

  def validate_dates!(fields)
    values = fields.select { |field| DATE_TYPES.include?(field['type']) }.filter_map { |field| @data[field['key']].presence }
    raise InvalidForm, '起始日期时间不能晚于结束日期时间' if values.size >= 2 && values.first > values.last
  end
end
