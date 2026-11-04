json.payload do
  json.partial! 'api/v1/models/crm_payroll_sheet', formats: [:json], resource: @sheet
  json.items do
    json.array!(@items || @sheet.items.ordered) do |it|
      json.partial! 'api/v1/models/crm_payroll_item', formats: [:json], resource: it
    end
  end
end
