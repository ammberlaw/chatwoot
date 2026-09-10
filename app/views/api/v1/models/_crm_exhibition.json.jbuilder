json.id resource.id
json.name resource.name
json.country resource.country
json.region resource.region
json.city resource.city
json.venue resource.venue
json.hall resource.hall
json.booth_no resource.booth_no
json.website resource.website
json.starts_on resource.starts_on
json.ends_on resource.ends_on
json.featured_products resource.featured_products
json.theme resource.theme
json.status resource.status
json.account_owner_id resource.account_owner_id
json.created_at resource.created_at
json.updated_at resource.updated_at

counts = resource.stage_counts
json.stage_counts do
  json.pending counts['pending'] || 0
  json.invited counts['invited'] || 0
  json.interacted counts['interacted'] || 0
  json.accepted counts['accepted'] || 0
  json.declined counts['declined'] || 0
end
json.invite_count counts.values.sum
