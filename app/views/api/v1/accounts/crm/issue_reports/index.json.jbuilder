json.counts @counts
json.payload do
  json.array! @reports do |report|
    json.partial! 'api/v1/accounts/crm/issue_reports/issue_report', formats: [:json], report: report
  end
end
