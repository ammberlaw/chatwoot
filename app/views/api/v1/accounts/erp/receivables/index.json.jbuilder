json.meta do
  json.count @receivables_count
  json.current_page params[:page] || 1
  json.total_micros @summary[:total_micros]
  json.received_micros @summary[:received_micros]
  json.outstanding_micros @summary[:total_micros].to_i - @summary[:received_micros].to_i
end
json.payload do
  json.array! @receivables do |receivable|
    json.partial! 'api/v1/models/erp_receivable', formats: [:json], resource: receivable, with_installments: true
  end
end
