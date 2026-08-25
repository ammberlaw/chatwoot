json.meta do
  json.as_of @report[:as_of]
  json.balanced @report[:balanced]
  json.totals @report[:totals]
end

json.sections do
  @report[:sections].each do |section, lines|
    json.set! section do
      json.label Erp::FinancialReportService::BS_SECTIONS[section]
      json.lines lines
      json.total_micros lines.sum { |line| line[:amount_micros] }
    end
  end
end
