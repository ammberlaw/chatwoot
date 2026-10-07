json.meta do
  json.as_of @report[:as_of]
  json.balanced @report[:balanced]
  json.totals @report[:totals]
  # 会企01 的表头三件：编制单位 / 报表日期 / 单位。编制单位取账套设置里的公司全称。
  json.form_code '会企01表'
  json.company_name Erp::Setting.for_account(Current.account).company_name
end

# 会企01 固定行式（行次与金蝶一致）：左资产、右负债和所有者权益，各含期末/年初两列。
json.asset_lines @report[:asset_lines]
json.equity_lines @report[:equity_lines]
# 没被任何报表行收走的科目：报表总计对得上、逐行却少一笔时，问题就在这儿。
json.unmapped @report[:unmapped]

json.sections do
  @report[:sections].each do |section, lines|
    json.set! section do
      json.label Erp::FinancialReportService::BS_SECTIONS[section]
      json.lines lines
      json.total_micros lines.sum { |line| line[:amount_micros] }
    end
  end
end
