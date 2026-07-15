json.id resource.id
json.crm_kpi_scheme_id resource.crm_kpi_scheme_id
json.scheme_name resource.scheme_name
json.period_month resource.period_month
json.status resource.status
json.pass_score resource.pass_score
json.item_score_cap_pct resource.item_score_cap_pct
json.total_score resource.total_score
json.monthly_salary_micros resource.monthly_salary_micros
json.performance_ratio resource.performance_ratio
json.baseline_target_micros resource.baseline_target_micros
json.performance_base_micros resource.performance_base_micros
json.payout_coefficient resource.payout_coefficient
json.actual_payout_micros resource.actual_payout_micros
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.manager_id resource.manager_id
json.manager_name resource.manager&.name
json.hr_id resource.hr_id
json.hr_name resource.hr&.name
json.gm_id resource.gm_id
json.gm_name resource.gm&.name
json.employee_signed_at resource.employee_signed_at
json.manager_signed_at resource.manager_signed_at
json.hr_confirmed_at resource.hr_confirmed_at
json.gm_confirmed_at resource.gm_confirmed_at
json.employee_signature_url resource.employee_signature.attached? ? url_for(resource.employee_signature) : nil
json.manager_signature_url resource.manager_signature.attached? ? url_for(resource.manager_signature) : nil
json.hr_signature_url resource.hr_signature.attached? ? url_for(resource.hr_signature) : nil
json.gm_signature_url resource.gm_signature.attached? ? url_for(resource.gm_signature) : nil
json.sheet_items resource.sheet_items.sort_by { |i| [i.sort_order || 0, i.id] } do |item|
  json.partial! 'api/v1/models/crm_kpi_sheet_item', formats: [:json], resource: item
end
