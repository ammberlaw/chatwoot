json.id @period.id
json.period @period.period
json.status @period.status
json.status_label Erp::FiscalPeriod::STATUS_LABELS[@period.status]
json.closed_at @period.closed_at
json.closing_voucher_no @period.closing_voucher&.voucher_no
json.reopened_at @period.reopened_at
