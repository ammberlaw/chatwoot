json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.operating_profit_micros @report[:operating_profit_micros]
  json.total_profit_micros @report[:total_profit_micros]
  json.net_profit_micros @report[:net_profit_micros]
end

json.payload @report[:rows]
