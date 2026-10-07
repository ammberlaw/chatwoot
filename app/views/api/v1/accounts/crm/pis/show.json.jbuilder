json.partial! 'api/v1/models/crm_pi', formats: [:json], resource: @pi

# 付款自动转单时回传新建订单，供前端提示并就地补填结算信息（未转则为 null）。
json.converted_order_no @converted_order&.order_no
json.converted_order_id @converted_order&.id
# 转单带不出来的那几项（结算方式 / 信保订单号）：PI 上没有结构化来源，只能转完让人补。
# 收款账户按 PI 抬头已自动带入，带不到（账套里没有对应账户）时也一并列出来。
json.converted_order_missing(@converted_order ? Crm::PiToSalesOrder::SETTLEMENT_FIELDS.reject { |f| @converted_order.public_send(f).present? } : [])
