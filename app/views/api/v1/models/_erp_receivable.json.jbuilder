json.id resource.id
json.receivable_no resource.receivable_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.crm_sales_order_id resource.crm_sales_order_id
json.order_no resource.crm_sales_order&.order_no
# 台账要能独立对账：PI 号是财务认的号，型号/日期/订单状态决定这笔钱该不该催、催谁。
# 没有这几列就只能逐条点进订单详情看，一张张对。
json.pi_no resource.crm_sales_order&.pi_no
json.order_status resource.crm_sales_order&.status
json.order_date resource.crm_sales_order&.order_date
json.delivery_date resource.crm_sales_order&.delivery_date
# 型号：列表只摆第一项 + 共几项，全部明细放 product_names 给悬浮用。
json.product_summary resource.crm_sales_order&.product_summary
json.product_names resource.crm_sales_order&.product_names
# 台账列表对标金蝶「销售出库明细」：信保单号、客户编码、业务员部门、出库单号/仓库、
# 税率、运费，都是财务拿旧表逐列对账时点名要的。
order = resource.crm_sales_order
json.insurance_order_no order&.insurance_order_no
json.customer_code resource.crm_customer&.customer_code
json.owner_department(
  if local_assigns.key?(:department_names)
    local_assigns[:department_names][resource.owner_id]
  else
    resource.owner && Org::Membership.where(account_id: resource.account_id, user_id: resource.owner_id)
                                     .order(is_primary: :desc).includes(:department).first&.department&.name
  end
)
# 税：订单上填了就用订单的，没填跟随账套默认（内销常报含税、外贸不含税，不能一个全局开关定死）。
json.tax_rate order&.effective_tax_rate
json.amount_includes_tax order&.effective_amount_includes_tax
# 客户承担的运费：订单金额是净销售不含运费，运费单列一栏。
json.shipping_micros order&.shipping_micros

# 订单明细直接摊在台账上（商品编码/品名/规格/单位/数量/单价/金额/事业部）——
# 财务要核「这笔钱是什么货、什么价」，以前只能逐条点进订单详情看。
# 单位和事业部挂在商品档上，按 sku 关联；手打的或已删的 sku 对不上就留空。
product_meta = local_assigns[:product_meta] || order&.product_meta_by_sku || {}
json.line_items((order&.line_item_rows || []).map { |item| item.merge(product_meta[item[:sku]] || {}) })

# 出库那张单：日期是账期起算日，单号/仓库是财务跟旧表对行用的。
# 列表页传 shipment_meta（一次查完），单条详情没传就现查。
shipment = (local_assigns.key?(:shipment_meta) ? local_assigns[:shipment_meta][resource.crm_sales_order_id] : order&.first_shipment_meta) || {}
json.shipped_on shipment[:shipped_on]
json.shipment_no shipment[:shipment_no]
json.warehouse_name shipment[:warehouse_name]
# 这笔应收在总账里有没有对应的收入凭证：建账时出的（Erp::Receivable）或出库时出的（Mes::Shipment）。
# 台账上看不出有没有入账，就只能去凭证列表逐条翻。
json.revenue_voucher_no resource.revenue_voucher&.voucher_no
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.total_amount_micros resource.total_amount_micros
json.received_amount_micros resource.received_amount_micros
json.outstanding_micros resource.outstanding_micros
json.status resource.status
json.status_label Erp::Receivable::STATUS_LABELS[resource.status]
json.owner_id resource.owner_id
# 财务看的一律中文优先（见 User#finance_display_name）
json.owner_name resource.owner&.finance_display_name
json.remark resource.remark

if local_assigns[:with_installments]
  json.installments do
    json.array! resource.installments do |installment|
      json.id installment.id
      json.seq installment.seq
      json.kind installment.kind
      json.kind_label Erp::ReceivableInstallment::KIND_LABELS[installment.kind]
      json.amount_micros installment.amount_micros
      json.due_basis installment.due_basis
      json.due_basis_label Erp::ReceivableInstallment::DUE_BASIS_LABELS[installment.due_basis]
      json.due_days installment.due_days
      json.due_date installment.due_date
      json.status installment.derived_status
      json.status_label Erp::ReceivableInstallment::STATUS_LABELS[installment.derived_status]
      json.remark installment.remark
    end
  end
end
