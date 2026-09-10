json.meta do
  # 建/改/删台账本仅财务与管理员；部门负责人只能在自己那本上记流水。
  json.can_manage @can_manage
end

json.payload do
  json.array! @books do |book|
    json.partial! 'api/v1/models/crm_petty_cash_book', formats: [:json], resource: book
    json.can_record @can_manage || @led_department_ids.include?(book.org_department_id)
  end
end
