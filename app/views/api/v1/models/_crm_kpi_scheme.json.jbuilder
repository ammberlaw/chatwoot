json.id resource.id
json.name resource.name
json.scheme_month resource.scheme_month
json.pass_score resource.pass_score
json.item_score_cap_pct resource.item_score_cap_pct
json.payout_note resource.payout_note
json.result_note resource.result_note
json.status resource.status
json.created_by_id resource.created_by_id
json.created_by_name resource.created_by&.name
json.scheme_items resource.scheme_items.sort_by { |i| [i.sort_order || 0, i.id] } do |item|
  json.partial! 'api/v1/models/crm_scheme_item', formats: [:json], resource: item
end
json.payout_tiers resource.payout_tiers.sort_by { |tt| [tt.sort_order || 0, tt.id] } do |tier|
  json.partial! 'api/v1/models/crm_payout_tier', formats: [:json], resource: tier
end
