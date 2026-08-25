json.meta do
  json.count @payables_count
  json.current_page params[:page] || 1
  json.total_micros @summary[:total_micros]
  json.paid_micros @summary[:paid_micros]
  json.outstanding_micros @summary[:total_micros].to_i - @summary[:paid_micros].to_i
end
json.payload do
  json.array! @payables do |payable|
    json.partial! 'api/v1/models/erp_payable', formats: [:json], resource: payable
  end
end
