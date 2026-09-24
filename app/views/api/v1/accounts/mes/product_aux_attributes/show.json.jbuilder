json.payload do
  json.partial! 'api/v1/models/crm_product_aux_attribute', formats: [:json], resource: @attribute
end
