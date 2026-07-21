json.meta do
  json.count @serial_numbers_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @serial_numbers do |sn|
    json.id sn.id
    json.sn sn.sn
    json.status sn.status
    json.product_name sn.crm_product&.name
    json.production_order_no sn.production_order&.order_no
    json.created_at sn.created_at
  end
end
