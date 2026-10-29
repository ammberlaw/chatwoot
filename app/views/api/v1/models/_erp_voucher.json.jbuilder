json.id resource.id
json.voucher_no resource.voucher_no
json.period resource.period
json.voucher_date resource.voucher_date
# 生成时间：自动凭证的凭证日期取来源单据的日期，和「什么时候生成的」常常不是一天。
# 列表要能按它排序/筛选，不下发的话前端无从分辨刚生成的是哪张。
json.created_at resource.created_at
json.status resource.status
json.status_label Erp::Voucher::STATUS_LABELS[resource.status]
json.summary resource.summary
json.remark resource.remark
json.attachment_count resource.attachment_count
# 原始单据影像；attachment_count 是纸面「附单据 N 张」，两回事，都要留。
# 列表只给张数（明细走 show，省得列表页每行都去查 blob）。
json.document_count resource.documents_attachments.size
json.source_type resource.source_type
json.source_id resource.source_id
json.total_debit_micros resource.total_debit_micros
json.total_credit_micros resource.total_credit_micros
json.balanced resource.balanced?
json.editable resource.editable?
json.prepared_by_name resource.prepared_by&.finance_display_name
json.posted_by_name resource.posted_by&.finance_display_name
json.posted_at resource.posted_at
json.reversal_of_no resource.reversal_of&.voucher_no
json.reversed_by_no resource.reversed_by&.voucher_no

if local_assigns[:with_lines]
  json.documents resource.documents.map { |doc|
    { id: doc.id, filename: doc.filename.to_s, byte_size: doc.byte_size,
      content_type: doc.content_type, url: rails_blob_path(doc, only_path: true) }
  }

  json.lines do
    json.array! resource.lines do |line|
      json.partial! 'api/v1/models/erp_voucher_line', formats: [:json], resource: line
    end
  end
end
