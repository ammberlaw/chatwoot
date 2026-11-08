json.customer do
  json.partial! 'api/v1/models/crm_customer', formats: [:json], resource: @customer
  # 详情页专用：最近联系时间（跟进/邮件/订单三者最新），覆盖 partial 里为 nil 的默认值。
  json.last_touch_at @last_touch_at
end

json.opportunities @opportunities do |opportunity|
  json.id opportunity.id
  json.name opportunity.name
  json.amount_micros opportunity.amount_micros
  json.currency opportunity.currency
  json.probability opportunity.probability
  json.sales_stage opportunity.sales_stage
  json.expected_close_date opportunity.expected_close_date
  json.next_action opportunity.next_action
  json.current_need opportunity.current_need
end

json.orders @orders do |order|
  json.id order.id
  json.order_no order.order_no
  json.name order.name
  json.pi_no order.pi_no
  json.order_amount_micros order.order_amount_micros
  json.order_currency order.order_currency
  json.order_date order.order_date
  json.delivery_date order.delivery_date
  json.status order.status
  json.files order.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
end

json.pis @pis do |pi|
  json.id pi.id
  json.pi_no pi.pi_no
  json.buyer pi.buyer_company.presence || pi.crm_customer&.name
  json.total_amount_micros pi.total_amount_micros
  json.currency pi.currency
  json.status pi.status
  json.pi_date pi.pi_date
end

json.quotes @quotes do |quote|
  json.id quote.id
  json.quote_no quote.quote_no
  json.name quote.name
  json.total_amount_micros quote.total_amount_micros
  json.quote_currency quote.quote_currency
  json.quote_date quote.quote_date
  json.status quote.status
end

# QC 质检影像，按生产订单分组（一单一行，点开才看图）。
# ⚠️ 只给图片和视频：质检结论、不良记录、返工原因是生产内部的事，
# 客户详情页业务条线也看得到，不往这儿带。
json.qc_media(@production_orders.map do |po|
  inspections = (@qc_media || {})[po.id] || []
  photos = inspections.flat_map do |i|
    i.photos.map do |f|
      { id: f.id, kind: 'photo', filename: f.filename.to_s,
        url: rails_blob_path(f, only_path: true), inspected_at: i.created_at }
    end
  end
  videos = inspections.flat_map do |i|
    i.videos.map do |f|
      { id: f.id, kind: 'video', filename: f.filename.to_s,
        url: rails_blob_path(f, only_path: true), inspected_at: i.created_at }
    end
  end
  next if photos.empty? && videos.empty?

  { production_order_id: po.id, order_no: po.order_no, product_name: po.product_name,
    photo_count: photos.size, video_count: videos.size, items: photos + videos }
end.compact)

json.production_orders @production_orders do |po|
  json.id po.id
  json.order_no po.order_no
  json.product_name po.product_name
  json.qty po.qty
  json.produced_qty po.produced_qty
  json.unit po.unit
  json.stage po.stage
  json.status po.status
  json.order_kind po.order_kind
  json.pi_no po.pi_no
  json.delivery_date po.delivery_date
  json.owner_name po.owner&.crm_display_name
end

json.notes @notes do |note|
  json.id note.id
  json.title note.title
  json.body note.body
  json.follow_up_method note.follow_up_method
  json.result_tag note.result_tag
  json.source note.source
  json.owner_name note.owner&.crm_display_name
  json.created_at note.created_at
end

json.tasks @tasks do |task|
  json.id task.id
  json.title task.title
  json.body task.body
  json.due_at task.due_at
  json.status task.status
  json.task_type task.task_type
  json.assignee_name task.assignee&.crm_display_name
end

# 寄样记录（右列那块）。复用 samples 的 partial，两处字段不会走偏。
json.samples @samples do |sample|
  json.partial! 'api/v1/accounts/crm/samples/sample', sample: sample
end
