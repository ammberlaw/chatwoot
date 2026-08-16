json.partial! 'api/v1/models/crm_pi', formats: [:json], resource: @pi

# 付款自动转单时，回传新建订单号供前端提示（未转则为 null）。
json.converted_order_no @converted_order&.order_no
