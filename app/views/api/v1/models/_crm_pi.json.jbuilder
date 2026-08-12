json.id resource.id
json.pi_no resource.pi_no
json.pi_date resource.pi_date
json.status resource.status
json.currency resource.currency
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.contact_id resource.contact_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_display_name
json.attention resource.attention
json.buyer_company resource.buyer_company
json.buyer_address resource.buyer_address
json.buyer_email resource.buyer_email
json.buyer_tel resource.buyer_tel
json.buyer_eori resource.buyer_eori
json.port_of_shipment resource.port_of_shipment
json.port_of_destination resource.port_of_destination
json.country_of_origin resource.country_of_origin
json.shipping_method resource.shipping_method
json.shipping_cost_label resource.shipping_cost_label
json.shipping_cost_micros resource.shipping_cost_micros
json.total_amount_micros resource.total_amount_micros
json.terms resource.terms
json.issued_by resource.issued_by
json.company_header resource.company_header
json.seller_mobile resource.seller_mobile
json.seller_email resource.seller_email
json.remark resource.remark
json.created_at resource.created_at
json.updated_at resource.updated_at
json.items resource.pi_items.map { |item|
  {
    id: item.id,
    position: item.position,
    model: item.model,
    description: item.description,
    quantity: item.quantity,
    unit_price_micros: item.unit_price_micros,
    amount_micros: item.amount_micros,
    picture_url: item.picture.attached? ? url_for(item.picture) : nil
  }
}
