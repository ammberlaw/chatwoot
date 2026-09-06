json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.fx_effect_micros @report[:fx_effect_micros]
  json.net_increase_micros @report[:net_increase_micros]
  json.opening_cash_micros @report[:opening_cash_micros]
  json.closing_cash_micros @report[:closing_cash_micros]
  json.variance_micros @report[:variance_micros]
  json.balanced @report[:balanced]
end

json.payload @report[:sections]
