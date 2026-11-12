# Immutable definition used by both historical rendering and attendance/finance integrations.
class Oa::TemplateSnapshot
  FIELDS = %w[id name revision form_fields flow attendance_kind cash_kind erp_expense cc_user_ids auto_approve overdue_hours].freeze
  attr_reader :data

  def initialize(data)
    @data = data.deep_stringify_keys
  end

  FIELDS.each { |field| define_method(field) { data[field] } }

  def self.capture(template, legacy: false, before_change: false)
    data = FIELDS.index_with { |field| before_change ? template.attribute_in_database(field) : template.public_send(field) }
    new(data.merge('legacy' => legacy)).data
  end
end
