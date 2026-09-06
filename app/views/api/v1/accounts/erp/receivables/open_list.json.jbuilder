json.payload do
  json.array! @receivables do |receivable|
    json.partial! 'api/v1/models/erp_receivable', formats: [:json], resource: receivable
  end
end
