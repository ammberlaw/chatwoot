json.meta do
  json.period @bad_debt[:period]
  json.as_of @bad_debt[:as_of]
  json.rates @bad_debt[:rates]
  json.buckets @bad_debt[:buckets]
  json.receivable_micros @bad_debt[:receivable_micros]
  json.required_micros @bad_debt[:required_micros]
  json.booked_micros @bad_debt[:booked_micros]
  json.adjustment_micros @bad_debt[:adjustment_micros]
  json.voucher_no @bad_debt[:voucher_no]
end

json.payload @bad_debt[:rows]
