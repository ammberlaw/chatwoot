json.partial! 'api/v1/models/mes_stock_entry', formats: [:json], resource: @stock_entry
# 过账成功、但应付台账没同步时的原因（见 Mes::StockEntry#sync_erp_payable）。
# 不弹出来的话，仓管只看到「已过账」，财务那边却少一笔欠款。
json.erp_payable_warning @stock_entry.erp_payable_warning if @stock_entry.erp_payable_warning.present?
