json.meta do
  json.count @payments_count
  json.current_page params[:page] || 1
  json.amount_micros @summary[:amount_micros]
end
json.payload do
  json.array! @payments do |payment|
    json.partial! 'api/v1/models/erp_payment_record', formats: [:json], resource: payment
  end
end
