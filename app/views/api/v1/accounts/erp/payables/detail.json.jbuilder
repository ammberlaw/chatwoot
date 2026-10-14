# 应付台账明细弹窗：这笔钱是哪张采购单、哪几行料、货到没到、付了几次。
json.payload do
  json.payable do
    json.partial! 'api/v1/models/erp_payable', formats: [:json], resource: @payable
  end

  po = @payable.mes_purchase_order
  if po
    json.purchase_order do
      json.id po.id
      json.po_no po.po_no
      # 发给这家供应商的那张子单号，供应商手上拿的就是它。
      json.supplier_po_no Mes::PoSupplierNumber.for(po, @payable.mes_supplier_id)
      json.doc_date po.created_at.to_date
      json.status po.status
      json.approval_status po.approval_status
      json.owner_name po.owner&.name
      json.production_order_no po.production_order&.order_no
      json.internal_remark po.internal_remark
      json.remark po.remark
    end
  end

  json.items @detail_items do |item|
    json.code item.crm_product&.sku.presence || item.mes_material&.material_no
    json.name item.crm_product&.name.presence || item.mes_material&.name
    json.spec item.mes_material&.specification.presence || item.crm_product&.specification
    json.unit item.unit
    json.quantity item.qty
    json.received_qty item.received_qty
    json.unit_price_micros item.rate_micros
    json.amount_micros item.amount_micros
    json.price_tax_included item.price_tax_included
    json.remark item.remark
  end

  # 入库单按整张采购单列（一张单多家供应商时也一起到货），标出过没过账。
  json.stock_entries @detail_entries do |entry|
    json.entry_no entry.entry_no
    json.status entry.status
    json.status_label({ 'DRAFT' => '草稿', 'POSTED' => '已过账', 'CANCELLED' => '已作废' }[entry.status])
    json.posted_at entry.posted_at
    json.actual_inbound_date entry.actual_inbound_date
  end

  json.payments @detail_allocations do |alloc|
    json.payment_no alloc.payment_record&.payment_no
    json.paid_at alloc.payment_record&.paid_at
    json.method_label alloc.payment_record && Erp::PaymentRecord::METHOD_LABELS[alloc.payment_record.method]
    json.amount_micros alloc.amount_micros
    json.remark alloc.payment_record&.remark
  end
end
