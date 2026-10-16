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
    json.warehouse_name @warehouse_names[entry.to_warehouse_id]
    json.remark entry.remark
    # 收了什么料：财务核应付时要对「收的货和这笔钱对不对得上」。
    # 这是应付侧，采购价本来就该看得到（销售端不可见那条约束不适用于财务/采购）。
    json.items entry.stock_entry_items do |item|
      src = item.mes_material || item.crm_product
      json.code src.try(:material_no) || src.try(:sku)
      json.name src&.name
      json.spec src.try(:specification)
      json.qty item.qty
      json.unit item.unit
    end
  end

  json.payments @detail_allocations do |alloc|
    pr = alloc.payment_record
    json.payment_no pr&.payment_no
    json.paid_at pr&.paid_at
    json.method_label pr && Erp::PaymentRecord::METHOD_LABELS[pr.method]
    json.amount_micros alloc.amount_micros
    json.remark pr&.remark
    # 点开要看的：这笔钱从哪个户出的、整笔付了多少（本次核销只是其中一部分）、
    # 手续费多少、银行流水号是什么——对账时就是照着这几项核的。
    json.cash_account_name pr&.cash_account&.name
    json.currency pr&.currency
    json.total_amount_micros pr&.amount_micros
    json.bank_charge_micros pr&.bank_charge_micros
    json.reference_no pr&.reference_no
    json.status pr&.status
  end
end
