json.id resource.id
json.shipment_no resource.shipment_no
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.crm_customer_id resource.crm_customer_id
# 客户名回落到销售订单上的客户：生产出库单建出来时不一定直接挂客户
# （挂的是生产订单），财务的出库审核页就只剩一个「—」，看不出这车货发给谁。
json.customer_name(resource.crm_customer&.name || resource.crm_sales_order&.crm_customer&.name)
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name mes_staff_name(resource.production_order&.owner)
json.warehouse_id resource.warehouse_id
json.kind resource.kind
json.status resource.status
json.notified_at resource.notified_at
json.submitted_at resource.submitted_at
json.approved_at resource.approved_at
json.manager_id resource.manager_id
json.manager_name mes_staff_name(resource.manager)
json.approve_note resource.approve_note
# 收款情况：财务审「款收齐没有」的依据，直接摆在审核弹窗上，不用去翻应收台账。
# 只在详情下发——列表逐行算回款进度是 N+1（每行要查应收 + 跑分期冲抵）。
if local_assigns[:detail]
  state = resource.receivable_state
  json.receivable_state state
  json.fully_paid state && state[:outstanding_micros].to_i <= 0
  # 收过哪几笔：日期 / 途径 / 金额。财务要对着银行流水一笔笔核才敢批，
  # 只给「应收·已收·还差」三个合计数她核不动（2026-10-29 反馈）。
  json.receipts resource.receipt_rows
  # 收款约定：这笔钱按什么方式收、收到哪个户。信保订单号在上面已单独下发。
  json.payment_term_label resource.payment_term_label
  json.receipt_account_name resource.receipt_account_name
end
json.reject_reason resource.reject_reason
# 作废留痕：谁废的、什么时候、为什么（列表上「已作废」那行要能说清楚）。
json.void_reason resource.void_reason
json.voided_at resource.voided_at
json.voided_by_name mes_staff_name(resource.voided_by)
# 谁能批这张单：财务始终能批；订单货款不超过 5000 美金 / 3 万人民币的，仓库自己批。
# warehouse_self_approvable 单独下发是给财务那张审核台用的——小额单打个标记，
# 让财务一眼看出哪些不用她管（仓库没动的她仍可兜底批）。
json.can_approve resource.approver_for?(Current.account_user)
json.warehouse_self_approvable resource.warehouse_self_approvable?
json.shipped_at resource.shipped_at
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::WAREHOUSE)
json.remark resource.remark
# 打印次数：仓库每月整叠打给财务核对，列表上要分出打过的和没打的。
json.print_count resource.print_count
# 发货仓 + 客户地址：销售出库单票面上要印「发货仓库」和「交货地点」，
# 原来这两样只能点进别处看。
json.warehouse_name resource.warehouse&.name
json.customer_address(resource.crm_customer&.address || resource.crm_sales_order&.crm_customer&.address)
json.sales_order_remark resource.crm_sales_order&.remark
# 出库审核页（财务）要的几项：这是谁的单、整张订单多少钱（本次出库常常只是其中一车）、
# 几号要交货。原先这页只有单号和客户名，连是哪个业务员都看不出来。
# 业务员取销售订单的 owner；生产出库单没挂销售订单时退回生产订单负责人——那张单
# 的 owner 就是业务员本人。两边都按 CRM 口径出名字，不要 production_order_owner_name
# 那个带岗位前缀的（财务看到「PMC-Oliver Sun」只会以为是另一个人）。
sales_order = resource.crm_sales_order
json.sales_owner_name((sales_order&.owner || resource.production_order&.owner)&.finance_display_name)
json.sales_order_date sales_order&.order_date
json.sales_delivery_date sales_order&.delivery_date
json.sales_order_amount_micros sales_order&.order_amount_micros
json.sales_order_currency sales_order&.order_currency
# 运费：订单金额是**净货款、不含运费**（运费在销售订单上单独一栏），
# 而客户打款是货款+运费一笔到账。财务审出库时要核的是「这单总共该收多少」，
# 只给货款就对不上收款（2026-10-29 财务反馈「缺少订单号，运费体现等关键信息」）。
json.sales_shipping_micros sales_order&.shipping_micros
json.sales_gross_micros((sales_order&.order_amount_micros.to_i + sales_order&.shipping_micros.to_i if sales_order))
# 信保订单号：业务在销售订单上填的那个（阿里信保单号），财务要拿它去平台上核。
# 本来就存在 crm_sales_orders 上，只是 MES 出库列表一直没把它带出来。
json.insurance_order_no sales_order&.insurance_order_no
# 交货方式（物流发货 / 车辆配送 / 客户自提）：仓管备货、派车、通知客户来提都看它，
# 不带出来的话他拿到出库单还得回订单里翻一遍。
json.delivery_method_label sales_order&.delivery_method_label
# 销售单价按订单明细里同一个产品那行取（出库单自己不存价）。
# 这是卖给客户的价，不是成本，销售端本来就看得到。
order_lines = sales_order&.line_item_rows.to_a
# 单价 vs 上次成交（财务放行前的异常提示）。只在详情算——出库审核页就是详情口径，
# 列表逐张算要扫 300 条历史。服务按币种缓存，一屏几张待审单只查一次。
price_marks = if local_assigns[:detail] && sales_order
                Crm::PriceBenchmark.new(resource.account).for_order(sales_order)
              else
                {}
              end
json.shipment_items do
  json.array! resource.shipment_items.order(:id) do |item|
    # 先按产品 id 对行（明细行基本都只存 id），对不上再退回 sku。
    line = order_lines.find { |r| r[:crm_product_id].present? && r[:crm_product_id].to_i == item.crm_product_id.to_i } ||
           order_lines.find { |r| r[:sku].present? && r[:sku] == item.crm_product&.sku }
    json.id item.id
    json.crm_product_id item.crm_product_id
    json.product_name item.crm_product&.name
    json.product_sku item.crm_product&.sku
    json.specification item.crm_product&.specification
    json.qty item.qty
    json.unit item.unit
    json.unit_price line&.dig(:unit_price)
    # 这行的价跟上次比高了还是低了。对不上订单行、或这个品名没历史就不给。
    mark = line && price_marks[line[:name]]
    json.price_benchmark mark&.to_h
    # 金额按**本次出库量**算，不是订单量——出库单上的钱是这一车货的钱。
    json.amount(line&.dig(:unit_price) ? (item.qty.to_d * line[:unit_price].to_d) : nil)
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
