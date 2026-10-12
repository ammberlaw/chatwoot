json.id resource.id
json.bom_no resource.bom_no
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.base_qty resource.base_qty
json.unit resource.unit
json.submit_date resource.submit_date
json.doc_no resource.doc_no
json.customer_name resource.customer_name
json.model resource.model
json.product_code resource.product_code
json.order_qty resource.order_qty
json.bare_color resource.bare_color
json.case_color resource.case_color
json.estimated_lead_days resource.estimated_lead_days
json.purchasing_days resource.purchasing_days
json.material_inbound_days resource.material_inbound_days
json.picking_days resource.picking_days
json.production_days resource.production_days
json.fg_inbound_days resource.fg_inbound_days
json.total_lead_days resource.total_lead_days
json.product_line resource.product_line
json.status resource.status
json.is_active resource.is_active
json.is_default resource.is_default
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::ENGINEERING)
json.sales_owner_id resource.sales_owner_id
json.sales_owner_name mes_staff_name(resource.sales_owner)
json.remark resource.remark
json.images(resource.images.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } })
json.files(resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } })
json.logos(resource.logos.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } })
onhand_map = resource.onhand_by_material_no
product_map = resource.product_info_by_material_no
# 成本只给财务/管理员/采购。拿不到权限就整个 price_map 为空，
# 每行的单价/金额键全是 nil，前端那两列自然不渲染。
bom_items = resource.bom_items.order(:id).to_a
price_map = if Current.account_user&.can_view_material_cost?
              # 传**全部**挂上来的生产订单，不是第一张：同一张任务单常分批下几张生产订单，
              # 各自采购价可能不同；只认第一张就按第一批的价算，后面几批的价全丢了。
              Mes::MaterialPriceResolver.new(account: resource.account, items: bom_items,
                                             production_orders: resource.production_orders.to_a).perform
            else
              {}
            end
json.bom_items do
  json.array! bom_items do |item|
    json.partial! 'api/v1/models/mes_bom_item', formats: [:json],
                                                resource: item, onhand_map: onhand_map,
                                                product_map: product_map, price_map: price_map
  end
end
# 成本小结：合计、单台成本、还有多少行没价。
# 「缺价行数」比合计本身更重要——不标出来，财务会把半截数当全的用。
json.cost do
  if price_map.any?
    material = bom_items.sum { |i| price_map[i.id] ? (i.qty.to_d * price_map[i.id][:price_micros]).round : 0 }
    std = resource.account.erp_bom_costs.find_by(crm_product_id: resource.crm_product_id)
    json.material_micros material
    json.process_micros std&.process_fee_micros.to_i
    json.overhead_micros std&.overhead_fee_micros.to_i
    json.total_micros material + std&.unit_cost_micros.to_i
    json.priced_lines price_map.size
    json.unpriced_lines bom_items.size - price_map.size
  else
    json.visible false
  end
end
json.revisions do
  json.array! resource.bom_revisions do |rev|
    json.id rev.id
    json.rev_no rev.rev_no
    json.reason rev.reason
    json.diff rev.diff
    json.changed_by_name mes_staff_name(rev.changed_by, Mes::StaffNames::ENGINEERING)
    json.created_at rev.created_at
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
