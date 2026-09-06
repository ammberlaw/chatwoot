json.meta do
  json.count @receipts_count
  json.current_page params[:page] || 1
  json.amount_micros @summary[:amount_micros]
end
json.payload do
  json.array! @receipts do |receipt|
    json.partial! 'api/v1/models/erp_receipt_record', formats: [:json], resource: receipt
  end
end
