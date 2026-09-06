json.payload do
  json.array! @payables do |payable|
    json.partial! 'api/v1/models/erp_payable', formats: [:json], resource: payable
  end
end
