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
# 已完工入库累计量：成品入库建单要用它算剩余，否则界面会把一张早已入满的订单
# 继续摆在下拉里、还把数量自动填成全量，引着人建出永远过不了账的重复单。
json.fg_inbound_qty (@fg_inbound_qty_by_order&.[](resource.id) || resource.fg_inbound_qty).to_f
json.progress_ratio resource.progress_ratio
# 列表对标金蝶生产任务单：规格型号 + 领料单数（领没领过料）。
# 未入库量 = 数量 − 已入库量，交前端算，不再多吐一个会算错口径的字段。
json.specification resource.crm_product&.specification
json.issued_entry_count (@issued_counts_by_order&.[](resource.id)).to_i
# 组装齐 / 包装齐：整机料、包装料分两组看到料到齐没有（Mes::KitReadiness）。
# ready 为 nil ＝ 没挂 BOM 或该类别没有料，前端不显示徽标——不能当成「齐了」。
if @kit_readiness
  state = @kit_readiness[resource.id] || {}
  json.kit_readiness do
    json.machine state[:machine] || { ready: nil, short: nil }
    json.packaging state[:packaging] || { ready: nil, short: nil }
  end
end
json.bom_id resource.bom_id
json.is_outsourced resource.is_outsourced
# 料是否都下满采购单：采购单的「关联生产订单」下拉据此把下完的单拿掉
# （否则选中后才弹「这张订单的料都已经下过采购单了」）。要展开 BOM 才算得出来，
# 只在列表显式要（with_purchasing_complete=1）时批量算一次。
json.purchasing_complete @purchasing_complete_ids.include?(resource.id) if @purchasing_complete_ids
# 下拉标注用：已下几张采购单 / 还差几项料 / 有没有挂生产任务单。
if @purchase_overview && (ov = @purchase_overview[resource])
  json.purchase_overview do
    json.po_count ov[:po_count]
    json.short_lines ov[:short_lines]
    json.no_bom ov[:no_bom]
  end
end
# 外购供应商含供应商资料，销售端不可见（生态硬约束）——仅 MES 员工下发。
if Current.account_user&.mes_staff?
  json.outsource_supplier_id resource.outsource_supplier_id
  json.outsource_supplier_name resource.outsource_supplier&.name
end
json.bom_no resource.bom&.bom_no
# 这张单的料卡在哪（按「等谁」归类汇总）。列表和详情都据此显示「3 项等业务文件 · 已卡 5 天」，
# 让相关的人一眼看出卡点不在采购身上（用户原话：「其余相关的人怎么看到这个单问题点卡在哪里」）。
json.blocker_summary resource.blocker_summary
json.blocked_item_count resource.blocked_item_count
# BOM 材料明细（该单用料，对标金蝶「材料明细」）：仅详情下发，列表不带以免 N+1。
if local_assigns[:detail]
  # 档案备注（工程写在产品上的工艺要求）按料号一次查出来，车间照着做，不用再跑产品档案。
  bom_product_map = resource.bom&.product_info_by_material_no || {}
  json.bom_items do
    json.array!((resource.bom&.bom_items&.order(:id)) || []) do |bi|
      json.material_no bi.material_no
      json.material_name bi.material_name
      json.specification bi.specification
      json.unit bi.unit
      json.qty bi.qty
      json.aux_attribute_name bi.aux_attribute_name
      json.remark bi.remark
      # 生产备注＝工程写给车间看的（只对内）；采购注意事项给采购，车间不用管。
      json.production_note bi.production_note
      json.purchase_note bi.purchase_note
      json.product_remark bom_product_map[bi.material_no]&.remark
    end
  end
end
# 业务二次确认 BOM（空 = 尚未确认，未确认前不得下发采购）。
json.bom_confirmed_at resource.bom_confirmed_at
json.bom_confirmed_by_name mes_staff_name(resource.bom_confirmed_by, Mes::StaffNames::ENGINEERING)
# BOM 变更史（工程改动已下发 BOM 的用料留痕；订单时间线可回看）。
json.bom_revisions do
  json.array! (resource.bom&.bom_revisions || []) do |rev|
    json.rev_no rev.rev_no
    json.reason rev.reason
    json.diff rev.diff
    json.changed_by_name mes_staff_name(rev.changed_by, Mes::StaffNames::ENGINEERING)
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
# 姓名带岗位（「工程-朱桂权」），岗位按当前阶段所属板块挑——身兼多岗的人在不同阶段显示不同岗位。
stage_hints = Mes::ProductionOrder::BOARD_ROLE_HINTS[Mes::ProductionOrder::STAGE_BOARD_KEYS[resource.stage]]
json.stage_owner_names mes_staff_names_for(resource.current_stage_owner_ids, stage_hints)
# 阶段负责人 {id,name} 配对（按 id 顺序，供详情面板点名字跳团队协同私聊；pluck 不保证同序，故单独配对）。
stage_owner_lookup = User.where(id: resource.current_stage_owner_ids).index_by(&:id)
# name 是纯姓名（前端拿首字做头像），label 才是带岗位的显示名。
json.stage_owners resource.current_stage_owner_ids.map { |uid|
  { id: uid, name: stage_owner_lookup[uid]&.name,
    label: mes_staff_label(uid, stage_owner_lookup[uid]&.name, stage_hints) }
}
json.awaiting_ack resource.awaiting_ack?
json.ack_overdue resource.ack_overdue?
json.ack_deadline resource.ack_deadline
# 退回给业务：工程/PMC 做任务单时发现业务没确认清楚，把单退回去等业务补细节。
# can_return 由模型按阶段 + 是不是本阶段负责人判（前端据此决定显不显示按钮）。
json.awaiting_sales_confirm resource.awaiting_sales_confirm?
# 业务二次确认用料（只卡有客户的单）：没确认就不许下发采购，见 ProductionOrder#confirm_bom!
json.bom_confirm_required resource.bom_confirm_required?
json.awaiting_bom_confirm resource.awaiting_bom_confirm?
json.bom_confirmed_at resource.bom_confirmed_at
json.bom_confirmed_by_name mes_staff_name(resource.bom_confirmed_by)
json.can_return_to_sales resource.can_return_to_sales?(Current.user)
# 「现在这个人能不能点」——带单据当下状态，不只判角色（App 据此显按钮/算待办）。
json.can_confirm_bom resource.can_confirm_bom?(Current.account_user)
json.can_resolve_sales_return resource.can_resolve_sales_return?(Current.account_user)
json.sales_return_at resource.sales_return_at
json.sales_return_reason resource.sales_return_reason
json.sales_return_by_name mes_staff_name(resource.sales_return_by)
json.sales_return_resolved_at resource.sales_return_resolved_at
json.stage_ack_at resource.stage_ack_at
json.stage_ack_by_name mes_staff_name(resource.stage_ack_by, stage_hints)
# 接单/转交流水：一个阶段两人接力时，各自的动作都要看得见（订单上的 stage_ack_* 只是当前状态）。
json.stage_ack_events do
  json.array! resource.stage_ack_events.chronological.includes(:actor, :to_user) do |ev|
    json.stage ev.stage
    json.kind ev.kind
    json.actor_name mes_staff_name(ev.actor)
    json.to_user_name mes_staff_name(ev.to_user)
    json.note ev.note
    json.happened_at ev.happened_at
  end
end
json.status resource.status
json.order_kind resource.order_kind
# 接单方式（新款/老款返单/样机）决定工程和 PMC 这两段谁要接单。
json.intake_kind resource.intake_kind
json.intake_label Mes::ProductionOrder::INTAKE_LABELS[resource.intake_kind]
# 当前这段归谁接（开头两段才分岗，其余阶段为 null）。
json.ack_role resource.ack_role
json.ack_role_label resource.ack_role_label
json.ack_skipped resource.ack_skipped?
json.delivery_date resource.delivery_date
json.planned_start_date resource.planned_start_date
json.planned_end_date resource.planned_end_date
json.actual_start_date resource.actual_start_date
json.actual_end_date resource.actual_end_date
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner)
json.is_draft resource.is_draft
json.pi_no resource.pi_no
json.product_code resource.product_code
# 审批链（取代发布）：状态 + 两级审批人 + 留痕。
json.approval_status resource.approval_status
json.current_approver_id resource.current_approver_id
json.submitted_at resource.submitted_at
json.manager_id resource.manager_id
json.manager_name mes_staff_name(resource.manager)
json.manager_acted_at resource.manager_acted_at
json.manager_comment resource.manager_comment
json.manager_acted_by_id resource.manager_acted_by_id
json.manager_acted_by_name mes_staff_name(resource.manager_acted_by)
json.gm_id resource.gm_id
json.gm_name mes_staff_name(resource.gm)
json.gm_acted_at resource.gm_acted_at
json.gm_comment resource.gm_comment
json.gm_acted_by_id resource.gm_acted_by_id
json.gm_acted_by_name mes_staff_name(resource.gm_acted_by)
json.spec resource.spec
json.remark resource.remark
# 相对路径（only_path）：绝对 url_for 会带 0.0.0.0:3000 宿主，浏览器加载不了。
json.images resource.images.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
# 关联采购单概要（一单多采购单：主料/辅料各一张，不同采购员）——供订单详情展示。
# 含采购员/采购信息，销售端不可见（生态硬约束）——仅 MES 员工下发，其余给空数组。
if Current.account_user&.mes_staff?
  pos = resource.purchase_orders.includes(:owner, purchase_items: %i[mes_material crm_product]).order(:created_at).to_a
  # 缺料清单只在详情里给：列表逐行展开每张采购单的明细，几百行的页面会被拖垮。
  shortages = local_assigns[:detail] ? Mes::KitShortage.by_purchase_order(pos) : {}
  json.purchase_orders pos do |po|
    json.id po.id
    json.po_no po.po_no
    json.status po.status
    json.owner_name mes_staff_name(po.owner, Mes::StaffNames::PURCHASING)
    json.item_count po.purchase_items.size
    json.shortages shortages[po.id] || []
  end
  # 物料到货明细：一张工单的料会摊成十几张入库单，逐张点开才数得清到了多少
  # （用户原话：「这1个工单原材料入库查找起来比较麻烦，都是一个一个的找」）。
  # 整机料 + 包装料一次列全，和缺料清单、齐套徽标同口径。只在详情给：要展开 BOM。
  json.material_arrivals(local_assigns[:detail] ? Mes::MaterialArrival.for(resource) : [])
else
  json.purchase_orders []
  json.material_arrivals []
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
      json.sender_name mes_staff_name(fwd.sender)
      json.created_at fwd.created_at
    end
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
