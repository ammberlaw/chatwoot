json.meta do
  json.count @pis_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @pis do |pi|
    json.partial! 'api/v1/models/crm_pi', formats: [:json], resource: pi
    # 已付款却没转出销售订单 = 转单静默失败，列表打红标（见 converted_pi_nos）。
    json.order_missing pi.status == 'PAID' && pi.pi_no.present? && !@converted_pi_nos.include?(pi.pi_no)
  end
end
