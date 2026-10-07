json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.operating_profit_micros @report[:operating_profit_micros]
  json.total_profit_micros @report[:total_profit_micros]
  json.net_profit_micros @report[:net_profit_micros]
  json.form_code '会企02表'
  json.company_name Erp::Setting.for_account(Current.account).company_name
end

# 会企02 固定行式（行次 1-45，行名与金蝶一致）。prior_amount_micros = 上年同期。
json.payload @report[:rows]
