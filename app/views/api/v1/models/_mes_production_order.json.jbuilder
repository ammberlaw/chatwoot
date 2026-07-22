json.id resource.id
json.order_no resource.order_no
json.product_line resource.product_line
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.crm_product_id resource.crm_product_id
json.product_name resource.product_name
json.qty resource.qty
json.unit resource.unit
json.produced_qty resource.produced_qty
json.progress_ratio resource.progress_ratio
json.bom_id resource.bom_id
json.bom_no resource.bom&.bom_no
json.stage resource.stage
json.stage_events do
  json.array! resource.stage_events.order(:entered_at) do |ev|
    json.stage ev.stage
    json.entered_at ev.entered_at
    json.note ev.note
  end
end
# 接单确认（P1）：当前阶段负责人 + 接单状态，供详情面板展示与接单/拒收按钮判定。
json.stage_owner_ids resource.current_stage_owner_ids
json.stage_owner_names User.where(id: resource.current_stage_owner_ids).pluck(:name)
json.awaiting_ack resource.awaiting_ack?
json.ack_overdue resource.ack_overdue?
json.ack_deadline resource.ack_deadline
json.stage_ack_at resource.stage_ack_at
json.stage_ack_by_name resource.stage_ack_by&.name
json.status resource.status
json.delivery_date resource.delivery_date
json.planned_start_date resource.planned_start_date
json.planned_end_date resource.planned_end_date
json.actual_start_date resource.actual_start_date
json.actual_end_date resource.actual_end_date
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.spec resource.spec
json.remark resource.remark
json.images resource.images.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
json.created_at resource.created_at
json.updated_at resource.updated_at
