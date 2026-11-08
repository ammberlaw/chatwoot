json.id resource.id
json.name resource.name
json.customer_code resource.customer_code
json.account_owner_id resource.account_owner_id
json.account_owner_name resource.account_owner&.crm_display_name
json.previous_owner_name resource.previous_owner&.crm_display_name
# 头像：列表里负责人/原跟进人那一格要显示本人头像，没上传才回落首字母。
# 不下发的话前端只能永远画首字母圈——用户上传了头像却到处看不到（2026-10-27 反馈）。
json.account_owner_avatar_url resource.account_owner&.avatar_url
json.previous_owner_avatar_url resource.previous_owner&.avatar_url
json.shared_user_ids resource.shared_user_ids || []
# 当前用户是否「特别关注」该客户（每人各标；@favorited_ids 由列表控制器预载，其他渲染处默认 false）。
json.favorited(@favorited_ids&.include?(resource.id) || false)

# 官网/地址/Linkedin：permit 里可写，这里必须一起吐出来——否则编辑弹窗回填为空，
# 一保存就把已有值清掉（AI 背调写进去的网址首当其冲）。
json.website resource.website
json.address resource.address
json.linkedin resource.linkedin

json.trade_country resource.trade_country
json.trade_region resource.trade_region
json.trade_city resource.trade_city

json.industry resource.industry
json.customer_level resource.customer_level
json.source_channel resource.source_channel
json.currency_preference resource.currency_preference
json.customer_status resource.customer_status
json.customer_group resource.customer_group
json.product_group resource.product_group
json.risk_level resource.risk_level

json.last_follow_up_at resource.last_follow_up_at
json.next_follow_up_at resource.next_follow_up_at
# AI「下一步建议」缓存（收信时顺手生成，详情页直接读，不实时调 AI）。
json.ai_next_step resource.ai_next_step
json.ai_next_step_at resource.ai_next_step_at
# 最近联系时间（跟进/往来邮件/订单三者取最新）：仅客户列表查询 select 了该别名，其余渲染处为 nil。
json.last_touch_at resource.attributes['last_touch_at']
json.is_in_public_pool resource.is_in_public_pool
json.public_pool_at resource.public_pool_at

json.primary_contact_name resource.primary_contact_name
json.contact_job_title resource.contact_job_title
json.contact_email resource.contact_email
json.contact_phone resource.contact_phone
json.whats_app resource.whats_app
json.wechat resource.wechat
json.alibaba_account resource.alibaba_account
# 欧盟增值税号。vat_verified_at 有值 = 过了欧盟官方 VIES 验证，
# 可以直接往形式发票上写；为空说明是人工填的，没验过。
# 背调摘要：主动开发建档时从线索带过来的（主营/可能采购/AI 判断/规模）。
# 这两列以前只写不读，2026-11-08 起在客户详情页显示。
json.labels resource.label_list
json.bg_summary resource.bg_summary
json.bg_checked_at resource.bg_checked_at
json.vat_no resource.vat_no
json.vat_verified_at resource.vat_verified_at
json.contact_preference resource.contact_preference
json.customer_remark resource.customer_remark

json.deal_total_amount_micros resource.deal_total_amount_micros
json.customer_star resource.customer_star
json.deal_order_count resource.deal_order_count
json.first_deal_at resource.first_deal_at
json.last_deal_at resource.last_deal_at

json.info_completeness_score resource.info_completeness_score
json.completeness_grade resource.completeness_grade

json.files resource.files.map { |f|
  meta = f.blob.metadata || {}
  {
    id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f),
    doc_type: meta['crm_doc_type'], doc_type_label: Crm::EmailAiService::DOC_TYPES[meta['crm_doc_type']],
    source: meta['crm_source'], email_subject: meta['crm_email_subject']
  }
}

json.created_at resource.created_at
json.updated_at resource.updated_at
