json.meta do
  json.count @requisitions_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @requisitions do |requisition|
    json.partial! 'api/v1/models/mes_purchase_requisition', formats: [:json], resource: requisition
  end
end
