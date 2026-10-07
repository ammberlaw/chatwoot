json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.fx_effect_micros @report[:fx_effect_micros]
  json.net_increase_micros @report[:net_increase_micros]
  json.opening_cash_micros @report[:opening_cash_micros]
  json.closing_cash_micros @report[:closing_cash_micros]
  json.variance_micros @report[:variance_micros]
  json.balanced @report[:balanced]
  # 会企03 表尾四行（32-35）的行次 + 表头三件。
  json.fx_effect_row_no @report[:fx_effect_row_no]
  json.net_increase_row_no @report[:net_increase_row_no]
  json.opening_row_no @report[:opening_row_no]
  json.closing_row_no @report[:closing_row_no]
  json.form_code @report[:form_code]
  json.company_name Erp::Setting.for_account(Current.account).company_name
end

json.payload @report[:sections]
