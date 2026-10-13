# 采购金额（含税单价/行金额/总额）属成本敏感信息：仅采购岗/财务/管理员/采购审批人可见，其余岗位(如仓管)不下发。
# 采购审批人也要看金额——不然审批时只看到物料不看到钱，批什么？（口径同 Mes::PurchaseOrderPolicy）
can_view_amount = Current.account_user&.mes_can?(:purchase) ||
                  Current.account_user&.crm_finance? ||
                  Mes::PurchaseOrder.approver?(Current.account, Current.user&.id) || false

json.id resource.id
json.po_no resource.po_no
json.supplier_names resource.purchase_items.filter_map { |i| i.mes_supplier&.name }.uniq
# 每家供应商在本单的专属单号（PU-20260928-04-01）：列表展开时要能一眼看出
# 发给哪家的是哪个号——供应商交货、仓库入库、财务对账都认它（Mes::PoSupplierNumber）。
json.suppliers do
  json.array!(resource.purchase_items.group_by(&:mes_supplier_id).map do |supplier_id, items|
    { id: supplier_id,
      no: Mes::PoSupplierNumber.for(resource, supplier_id),
      name: items.first.mes_supplier&.name || '未指定供应商' }
  end.sort_by { |s| s[:no] })
end
json.production_order_id resource.production_order_id
json.product_line resource.product_line
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name mes_staff_name(resource.production_order&.owner)
json.status resource.status
json.approval_status resource.approval_status
json.submitted_at resource.submitted_at
json.gm_id resource.gm_id
json.gm_name mes_staff_name(resource.gm)
json.gm_acted_at resource.gm_acted_at
json.gm_comment resource.gm_comment
json.current_approver_id resource.current_approver_id
json.expected_date resource.expected_date
json.follow_up_date resource.follow_up_date
json.delivery_date resource.delivery_date
# 单据日期＝下单那天（对标金蝶的「单据日期」）。交货时间/回复交期是另两件事，
# 列表上一直没有「这单什么时候下的」，对账时排不出先后。
json.doc_date resource.created_at&.to_date
json.has_exception resource.has_exception
json.exception_note resource.exception_note
json.total_amount_micros can_view_amount ? resource.total_amount_micros : nil
json.can_view_amount can_view_amount
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::PURCHASING)
json.remark resource.remark
# 对内备注：只在系统里给采购/生产看（哪几张单在用这批料），发给供应商的模板不取它。
json.internal_remark resource.internal_remark
# 预览/导出次数：一个供应商几十张单时，用来看哪张还没导出转发过。
json.export_count resource.export_count
json.last_exported_at resource.last_exported_at
# 额外关联的生产订单（同款物料多单共用一次采购）。
json.extra_production_order_ids resource.extra_production_order_ids
json.related_production_order_nos(
  if resource.extra_production_order_ids.present?
    resource.related_production_orders.map(&:order_no)
  else
    [resource.production_order&.order_no].compact
  end
)
json.purchase_items do
  json.array! resource.purchase_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_purchase_item', formats: [:json], resource: item, can_view_amount: can_view_amount
  end
end
json.partial! 'api/v1/models/mes_return_state', formats: [:json], resource: resource
json.created_at resource.created_at
json.updated_at resource.updated_at
