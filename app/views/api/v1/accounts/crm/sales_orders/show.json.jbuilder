json.partial! 'api/v1/models/crm_sales_order', formats: [:json], resource: @sales_order
# 库存单审核通过会自动转出库单（见 Crm::StockOrderAutoConvert）：成功或没转成的原因
# 要让审核人当场看见，否则他只知道「审核通过」，不知道单子转没转。
json.auto_convert_note @auto_convert_note if @auto_convert_note.present?
