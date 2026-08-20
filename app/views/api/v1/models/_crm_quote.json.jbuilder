json.id resource.id
json.name resource.name
json.quote_no resource.quote_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.contact_id resource.contact_id
json.crm_opportunity_id resource.crm_opportunity_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_display_name
json.owner_avatar_url resource.owner&.avatar_url
json.handled_by_id resource.handled_by_id
json.handled_by_name resource.handled_by&.crm_display_name
json.contact_name resource.contact&.name
json.quote_date resource.quote_date
json.valid_until resource.valid_until
json.status resource.status
json.quote_currency resource.quote_currency
json.exchange_rate resource.exchange_rate
json.subtotal_micros resource.subtotal_micros
json.discount_amount_micros resource.discount_amount_micros
json.shipping_fee_micros resource.shipping_fee_micros
json.tax_amount_micros resource.tax_amount_micros
json.total_amount_micros resource.total_amount_micros
json.line_items_count resource.line_items.size
json.line_items do
  json.array! resource.line_items.order(:id) do |item|
    json.partial! 'api/v1/models/crm_quote_line_item', formats: [:json], resource: item
  end
end
json.remark resource.remark
json.updated_at resource.updated_at
