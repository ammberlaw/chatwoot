json.meta do
  json.period @revaluation[:period]
  json.as_of @revaluation[:as_of]
  json.currencies @revaluation[:currencies]
  json.rates_ready @revaluation[:rates_ready]
  json.rates @revaluation[:rates]
  json.total_diff_micros @revaluation[:total_diff_micros]
  json.voucher_no @revaluation[:voucher_no]
  json.count @revaluation[:count]
end

json.payload @revaluation[:rows]
