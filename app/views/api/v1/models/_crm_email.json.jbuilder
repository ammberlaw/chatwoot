json.id resource.id
json.subject resource.subject
json.folder resource.folder
json.is_read resource.is_read
json.is_starred resource.is_starred
json.from_address resource.from_address
json.to_address resource.to_address
json.cc_address resource.cc_address
json.bcc_address resource.bcc_address
json.email_date resource.email_date
json.body resource.body
json.body_html resource.body_html
json.send_status resource.send_status
json.send_error resource.send_error
json.scheduled_at resource.scheduled_at
json.reply_latency_hours resource.reply_latency_hours
json.tracked resource.tracking_token.present?
json.open_count resource.open_count
json.click_count resource.click_count
json.first_opened_at resource.first_opened_at
json.last_opened_at resource.last_opened_at
last_open = local_assigns[:last_open]
json.last_open_country last_open&.country
json.last_open_city last_open&.city
json.label_ids resource.label_ids
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
# 客户当地时间要用：邮件头的时区入库时已折成 UTC，国家是唯一能稳定拿到的地理信息。
json.customer_country resource.crm_customer&.trade_country
# 发件人时区偏移（分钟，来自 Date 头）：没建档的客户靠它算当地时间。老邮件为 nil。
json.sender_utc_offset_minutes resource.sender_utc_offset_minutes
json.contact_id resource.contact_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_display_name
json.counterparty_type local_assigns[:counterparty_type]
# 列表显示用：业务员备注的联系人名/客户名，认不出时前端退回显示邮箱地址。
json.counterparty_name local_assigns[:counterparty_name]
# 内部分发去向：列表上直接标出这封分给了谁 / 是谁分给我的（同会话卡片标业务的做法）。
distributions = local_assigns[:distributions] || []
json.distributed_to distributions.filter_map { |d| d.to_user&.crm_display_name }
json.distributed_by distributions.first&.from_user&.crm_display_name
json.distributed_to_me distributions.any? { |d| d.to_user_id == Current.user&.id }
# 内联图（签名 logo、客户嵌在正文里的图）本该只出现在正文中、不混进附件列表。
# 但正文一旦被截断或 cid 改写失败，引用就没了——图片躺在库里却哪儿都看不见。
# 所以只隐藏「正文确实引用到了的」那些，引用不到的一律当普通附件露出来。
visible_files = resource.files.reject do |f|
  f.blob.metadata['inline'] && resource.body_html.to_s.include?(f.blob.signed_id)
end
json.files(visible_files) do |f|
  json.id f.id
  json.filename f.filename.to_s
  json.byte_size f.byte_size
  json.content_type f.content_type
  # 强制 attachment disposition：否则 PDF 被 ActiveStorage 当可内联类型发 inline，
  # 浏览器下载时用 URL 里的 blob key 当文件名（乱码），而 docx/xlsx 默认 attachment 正常。
  # 前端预览另走 fetch→blob，不受此影响。
  json.url rails_blob_url(f, disposition: 'attachment')
end
json.created_at resource.created_at
