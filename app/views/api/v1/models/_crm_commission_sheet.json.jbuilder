json.id resource.id
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.period_month resource.period_month
json.status resource.status
json.manager_id resource.manager_id
json.manager_name resource.manager&.name
json.submitted_at resource.submitted_at
json.approved_at resource.approved_at
json.returned_at resource.returned_at
json.returned_by_name resource.returned_by&.name
json.return_reason resource.return_reason
json.remark resource.remark
json.paid_at resource.paid_at
json.paid_by_name resource.paid_by&.name
json.paid_amount_micros resource.paid_amount_micros
json.paid_note resource.paid_note
json.totals resource.totals
json.created_at resource.created_at
json.updated_at resource.updated_at
json.items do
  json.array! resource.items do |item|
    json.partial! 'api/v1/models/crm_commission_item', formats: [:json], resource: item
  end
end
