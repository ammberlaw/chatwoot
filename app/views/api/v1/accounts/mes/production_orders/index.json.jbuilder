json.meta do
  json.count @production_orders_count
  json.hidden_no_line @hidden_no_line
  json.current_page params[:page] || 1
  # 「业务员」下拉用：实际当过订单归属人的 user_id（前端据此兜底，见控制器注释）。
  json.owner_ids @owner_ids
end

json.payload do
  json.array! @production_orders do |production_order|
    json.partial! 'api/v1/models/mes_production_order', formats: [:json], resource: production_order
  end
end
