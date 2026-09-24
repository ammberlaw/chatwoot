json.id resource.id
json.order_no resource.order_no
json.product_line resource.product_line
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.customer_country resource.crm_customer&.trade_country
json.crm_product_id resource.crm_product_id
json.product_name resource.product_name
# 商品编码 = 关联产品档案(crm_product)的 sku，全站统一用这个作为「商品编码」。
json.product_sku resource.crm_product&.sku
json.qty resource.qty
json.unit resource.unit
json.produced_qty resource.produced_qty
json.progress_ratio resource.progress_ratio
json.bom_id resource.bom_id
json.is_outsourced resource.is_outsourced
# 外购供应商含供应商资料，销售端不可见（生态硬约束）——仅 MES 员工下发。
if Current.account_user&.mes_staff?
  json.outsource_supplier_id resource.outsource_supplier_id
  json.outsource_supplier_name resource.outsource_supplier&.name
end
json.bom_no resource.bom&.bom_no
# BOM 材料明细（该单用料，对标金蝶「材料明细」）：仅详情下发，列表不带以免 N+1。
if local_assigns[:detail]
  json.bom_items do
    json.array!((resource.bom&.bom_items&.order(:id)) || []) do |bi|
      json.material_no bi.material_no
      json.material_name bi.material_name
      json.specification bi.specification
      json.unit bi.unit
      json.qty bi.qty
    end
  end
end
# 业务二次确认 BOM（空 = 尚未确认，未确认前不得下发采购）。
json.bom_confirmed_at resource.bom_confirmed_at
json.bom_confirmed_by_name resource.bom_confirmed_by&.name
# BOM 变更史（工程改动已下发 BOM 的用料留痕；订单时间线可回看）。
json.bom_revisions do
  json.array! (resource.bom&.bom_revisions || []) do |rev|
    json.rev_no rev.rev_no
    json.reason rev.reason
    json.diff rev.diff
    json.changed_by_name rev.changed_by&.name
    json.created_at rev.created_at
  end
end
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
# 阶段负责人 {id,name} 配对（按 id 顺序，供详情面板点名字跳团队协同私聊；pluck 不保证同序，故单独配对）。
stage_owner_lookup = User.where(id: resource.current_stage_owner_ids).index_by(&:id)
json.stage_owners resource.current_stage_owner_ids.map { |uid| { id: uid, name: stage_owner_lookup[uid]&.name } }
json.awaiting_ack resource.awaiting_ack?
json.ack_overdue resource.ack_overdue?
json.ack_deadline resource.ack_deadline
json.stage_ack_at resource.stage_ack_at
json.stage_ack_by_name resource.stage_ack_by&.name
# 接单/转交流水：一个阶段两人接力时，各自的动作都要看得见（订单上的 stage_ack_* 只是当前状态）。
json.stage_ack_events do
  json.array! resource.stage_ack_events.chronological.includes(:actor, :to_user) do |ev|
    json.stage ev.stage
    json.kind ev.kind
    json.actor_name ev.actor&.name
    json.to_user_name ev.to_user&.name
    json.note ev.note
    json.happened_at ev.happened_at
  end
end
json.status resource.status
json.order_kind resource.order_kind
json.delivery_date resource.delivery_date
json.planned_start_date resource.planned_start_date
json.planned_end_date resource.planned_end_date
json.actual_start_date resource.actual_start_date
json.actual_end_date resource.actual_end_date
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.is_draft resource.is_draft
json.pi_no resource.pi_no
json.product_code resource.product_code
# 审批链（取代发布）：状态 + 两级审批人 + 留痕。
json.approval_status resource.approval_status
json.current_approver_id resource.current_approver_id
json.submitted_at resource.submitted_at
json.manager_id resource.manager_id
json.manager_name resource.manager&.name
json.manager_acted_at resource.manager_acted_at
json.manager_comment resource.manager_comment
json.gm_id resource.gm_id
json.gm_name resource.gm&.name
json.gm_acted_at resource.gm_acted_at
json.gm_comment resource.gm_comment
json.spec resource.spec
json.remark resource.remark
# 相对路径（only_path）：绝对 url_for 会带 0.0.0.0:3000 宿主，浏览器加载不了。
json.images resource.images.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
# 关联采购单概要（一单多采购单：主料/辅料各一张，不同采购员）——供订单详情展示。
# 含采购员/采购信息，销售端不可见（生态硬约束）——仅 MES 员工下发，其余给空数组。
if Current.account_user&.mes_staff?
  json.purchase_orders resource.purchase_orders.includes(:owner, :purchase_items).order(:created_at) do |po|
    json.id po.id
    json.po_no po.po_no
    json.status po.status
    json.owner_name po.owner&.name
    json.item_count po.purchase_items.size
  end
else
  json.purchase_orders []
end
# 业务转发/知会：可转发的阶段板块（含当前负责人姓名）+ 已知会留痕。仅详情(show)输出，
# 避免列表逐行跑 board_owner 查询（N+1）。
if local_assigns[:detail]
  json.forward_targets resource.forward_targets
  json.order_forwards do
    json.array! resource.order_forwards do |fwd|
      json.id fwd.id
      json.board_key fwd.board_key
      json.stage_label fwd.stage_label
      json.recipient_names fwd.recipient_names
      json.note fwd.note
      json.sender_name fwd.sender&.name
      json.created_at fwd.created_at
    end
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
