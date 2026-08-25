json.meta do
  json.count @vouchers_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @vouchers do |voucher|
    json.partial! 'api/v1/models/erp_voucher', formats: [:json], resource: voucher
  end
end
