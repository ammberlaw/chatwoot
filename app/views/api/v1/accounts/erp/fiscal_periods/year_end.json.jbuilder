json.meta do
  json.year @year_end[:year]
  json.as_of @year_end[:as_of]
  json.profit_micros @year_end[:profit_micros]
  json.surplus_rate @year_end[:surplus_rate]
  json.surplus_micros @year_end[:surplus_micros]
  json.retained_micros @year_end[:retained_micros]
  json.voucher_no @year_end[:voucher_no]
  json.unclosed_periods @year_end[:unclosed_periods]
end
