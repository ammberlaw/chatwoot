json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/models/erp_voucher_template', formats: [:json], resource: template
  end
end
