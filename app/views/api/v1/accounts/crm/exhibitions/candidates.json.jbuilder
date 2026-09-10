json.payload do
  json.array! @candidates do |c|
    json.id c.id
    json.name c.name
    json.trade_country c.trade_country
    json.trade_region c.trade_region
    json.industry c.industry
    json.product_group c.product_group
    json.customer_level c.customer_level
    json.primary_contact_name c.primary_contact_name
    json.contact_email c.contact_email
    json.whats_app c.whats_app
    json.deal_total_amount_micros c.try(:deal_total_amount_micros)
    json.match_level c.match_level
  end
end
