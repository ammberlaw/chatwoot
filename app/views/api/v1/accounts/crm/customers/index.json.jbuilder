json.meta do
  json.count @customers_count
  json.current_page params[:page] || 1
  # 流失预警视图：把判定规则原文一起带出去，页面副标题直接渲染（见 churn_rule）。
  json.churn_rule @churn_rule if @churn_rule
end

json.payload do
  json.array! @customers do |customer|
    json.partial! 'api/v1/models/crm_customer', formats: [:json], resource: customer
  end
end
