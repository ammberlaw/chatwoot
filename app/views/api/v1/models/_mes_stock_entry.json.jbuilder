json.id resource.id
json.entry_no resource.entry_no
json.purpose resource.purpose
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name resource.production_order&.owner&.name
json.product_name resource.production_order&.product_name
json.product_sku resource.production_order&.crm_product&.sku
# 关联采购单（采购来源）属采购口径，销售端不可见（生态硬约束）——仅 MES 员工下发。
if Current.account_user&.mes_staff?
  json.purchase_order_id resource.purchase_order_id
  json.purchase_order_no resource.purchase_order&.po_no
end
json.from_warehouse_id resource.from_warehouse_id
json.to_warehouse_id resource.to_warehouse_id
json.status resource.status
json.posted_at resource.posted_at
json.actual_inbound_date resource.actual_inbound_date
json.color resource.color
json.workshop_confirmed_at resource.workshop_confirmed_at
json.workshop_confirmed_by_name resource.workshop_confirmed_by&.name
json.warehouse_confirmed_at resource.warehouse_confirmed_at
json.warehouse_confirmed_by_name resource.warehouse_confirmed_by&.name
# 财务审核（只原料入库走，见 Mes::StockEntry::APPROVAL_REQUIRED_PURPOSES）。
# can_approve 下发给前端决定出不出「通过/驳回」按钮——后端 ensure_approver! 仍会再判一次。
json.needs_approval resource.needs_approval?
json.approval_status resource.approval_status
json.approved_at resource.approved_at
json.approved_by_name resource.approved_by&.name
json.reject_reason resource.reject_reason
json.can_approve resource.needs_approval? &&
  Mes::StockEntry.approver?(Current.account, Current.account_user)
json.is_checked resource.is_checked
json.checked_by_id resource.checked_by_id
json.checked_by_name resource.checked_by&.name
json.received_by_id resource.received_by_id
json.received_by_name resource.received_by&.name
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
# 入库单要能独立成单：供应商、规格型号、单价、金额原本都只在采购单上，
# 仓管核料、财务对账都得另开一张采购单比着看。这里按来源采购单补齐。
#
# 单价/金额沿用采购口径的权限闸（仅采购岗/财务/管理员/采购审批人）——
# 入库单给仓管看得最多，不能顺手把成本漏出去。
po = resource.purchase_order
# 来源采购单的行先取出来：供应商名、单价都从这里对
purchase_items = po ? po.purchase_items.to_a : []
can_view_amount = Current.account_user&.mes_can?(:purchase) ||
                  Current.account_user&.crm_finance? ||
                  Mes::PurchaseOrder.approver?(Current.account, Current.user&.id) || false
# 供应商对销售端不可见——与抬头那串 supplier_names 同一道口子，行上也得关。
can_view_supplier = Current.account_user&.mes_staff? || false
# 行 → 采购行的对应：同一张采购单里按物料/成品对上，对不上就留空（手工建的入库单没有来源行）。
entry_items = resource.stock_entry_items.order(:id).to_a
match_po_item = lambda do |item|
  purchase_items.find do |pi|
    (item.mes_material_id.present? && pi.mes_material_id == item.mes_material_id) ||
      (item.crm_product_id.present? && pi.crm_product_id == item.crm_product_id)
  end
end
if can_view_supplier
  # 抬头这串供应商只列**本单收到的这几行料**的供应商，不是整张采购单上的全部。
  # 原来按整单列：一张采购单十几家供应商、这张入库单只收了两颗料，抬头却列出十几家，
  # 跟下面的收货明细对不上，没法对账（用户点名）。
  json.supplier_names entry_items.filter_map { |item| match_po_item.call(item)&.mes_supplier&.name }.uniq
  # 对内备注：核对入库时要看的就是这句（反馈点名要显示出来）。
  json.internal_remark po&.internal_remark
end
item_meta = lambda do |item|
  hit = match_po_item.call(item)
  {
    supplier_name: can_view_supplier ? hit&.mes_supplier&.name : nil,
    # 源单号是**这家供应商**的那张单（PU-20260928-04-01）：仓库按供应商交来的那张单核对，
    # 一张采购单含多家供应商时，整单 po_no 对不上他手里的单（见 Mes::PoSupplierNumber）。
    source_po_no: hit && can_view_supplier ? Mes::PoSupplierNumber.for(po, hit.mes_supplier_id) : nil,
    specification: item.mes_material&.specification.presence || item.crm_product&.specification,
    unit_price_micros: can_view_amount ? hit&.rate_micros : nil,
    # 金额按**本次入库量**算，不是采购量——入库单上的钱是这一车货的钱。
    amount_micros: (can_view_amount && hit&.rate_micros ? (item.effective_qty.to_d * hit.rate_micros).round : nil)
  }
end
json.can_view_amount can_view_amount
json.stock_entry_items do
  json.array! entry_items do |item|
    json.partial! 'api/v1/models/mes_stock_entry_item', formats: [:json], resource: item,
                                                        meta: item_meta.call(item)
  end
end
json.partial! 'api/v1/models/mes_return_state', formats: [:json], resource: resource
json.receipts resource.receipts.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
json.created_at resource.created_at
json.updated_at resource.updated_at
