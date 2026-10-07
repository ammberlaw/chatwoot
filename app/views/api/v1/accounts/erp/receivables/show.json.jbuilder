json.partial! 'api/v1/models/erp_receivable', formats: [:json], resource: @receivable, with_installments: true
# 建账成功但收入凭证没出来时的原因，前端照原样提示（见 Erp::LedgerBuilderService#voucher_warning）。
json.voucher_warning @voucher_warning if @voucher_warning.present?
