json.partial! 'api/v1/models/erp_expense_payout', formats: [:json], resource: @payout
# 作废时若凭证已过账，自动凭证不会被动掉——把凭证号回给前端提示财务去红冲。
json.posted_voucher_no @posted_voucher_no if @posted_voucher_no.present?
