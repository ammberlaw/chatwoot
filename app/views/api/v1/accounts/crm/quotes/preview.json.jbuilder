# 报价单在线预览：单据本体 + 模板里固定不变的抬头/条款文案，供前端 1:1 排版。
json.partial! 'api/v1/models/crm_quote', formats: [:json], resource: @quote

json.buyer do
  json.contact_name @buyer_contact
  json.company @quote.crm_customer&.name
  json.country @quote.crm_customer&.trade_country
  json.email @quote.crm_customer&.contact_email
  json.tel @quote.crm_customer&.contact_phone
  json.website @quote.crm_customer&.website
end

json.seller do
  json.contact_line @seller_lines[0]
  json.email_line @seller_lines[1]
end

json.issued_by @issuer_name

# 小计 / 运费 / 总额：与导出同口径——运费＝总额−各行小计（含折扣、税的净额）。
# 用局部变量算好再赋值：直接把带块的 sum 当参数传给 jbuilder，块会被当成嵌套对象写法。
subtotal_micros = @quote.line_items.sum { |li| li.amount_micros.to_i }
json.subtotal_micros subtotal_micros
json.freight_micros @quote.total_amount_micros.to_i - subtotal_micros

json.template do
  json.merge! @static
end
