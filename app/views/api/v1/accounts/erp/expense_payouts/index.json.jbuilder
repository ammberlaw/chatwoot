json.meta do
  json.count @payouts_count
  json.current_page params[:page] || 1
  json.amount_micros @summary[:amount_micros]
end
json.payload do
  json.array! @payouts do |payout|
    json.partial! 'api/v1/models/erp_expense_payout', formats: [:json], resource: payout
  end
end
