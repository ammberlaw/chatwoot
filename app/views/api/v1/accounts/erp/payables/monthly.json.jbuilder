json.meta do
  json.as_of @monthly[:as_of]
  json.months @monthly[:months]
  json.earlier_key @monthly[:earlier_key]
  json.totals @monthly[:totals]
end

json.payload do
  json.array! @monthly[:rows] do |row|
    json.supplier_id row.supplier_id
    json.supplier_name row.supplier_name
    json.settle_type row.settle_type
    json.settle_type_label Erp::Payable::SETTLE_TYPE_LABELS[row.settle_type]
    json.by_month row.by_month
    json.total_micros row.total_micros
  end
end
