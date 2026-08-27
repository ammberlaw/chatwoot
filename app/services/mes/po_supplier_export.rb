require 'zip'
require 'csv'

# 采购单按供应商拆分导出：一张采购单里各供应商的料各成一份，打包成 zip、直接转发给对应供应商。
# 每份只含该供应商的物料，绝不带其他供应商 / 关联生产订单 / 成本毛利。
# 抬头/税口径按【每个供应商档案上的 bill_entity】自动选（同一张单可含税、未税供应商混排）。
#
# 【当前为 interim 版：产物是 CSV（UTF-8 BOM，Excel 可直接打开中文）】——先把「按供应商拆分 + 打包 + 下载」
# 跑通。待公司采购单/合同 .xlsx 模板到位（放 lib/purchase_order/），把 supplier_doc 换成填模板即可
# （照 Crm::PiTemplateFiller 那套 rubyzip 改 XML），文件名后缀改回 .xlsx、content_type 换成 xlsx。
class Mes::PoSupplierExport
  # 开票主体（抬头）：决定公司名 / 单据名 / 税口径。取自供应商档案 bill_entity。
  HEADERS = {
    'wintouch' => { company: '深圳联合触控科技有限公司', title: '采购订单', taxed: false, currency: '不含税 RMB' },
    'liontek' => { company: '东莞市联迪科技有限公司', title: '采购合同', taxed: true, currency: '含税 RMB' }
  }.freeze
  TAX_RATE = 1.13 # 联迪含税 13%：未税价 × 1.13 = 含税价

  def initialize(purchase_order)
    @po = purchase_order
  end

  # 按供应商分组的结构化数据（供前端渲染 PDF：每供应商一张 PO，未税/含税抬头按 bill_entity）。
  # 价按抬头口径算好（联迪含税 = 未税 ×1.13），前端只渲染不计算；绝不含成本/毛利/其他供应商。
  def payload
    {
      po_no: @po.po_no,
      date: @po.created_at&.to_date&.to_s,
      delivery_date: @po.delivery_date&.to_s,
      suppliers: grouped.map { |_id, items| supplier_payload(items) }
    }
  end

  # 返回打包好的 zip（每供应商一个文件）IO 流。
  def to_zip_stream
    groups = @po.purchase_items
                .includes(:mes_material, :crm_product, :mes_supplier)
                .group_by(&:mes_supplier_id)
    buffer = Zip::OutputStream.write_buffer do |zip|
      used = Hash.new(0) # 供应商同名去重（文件名不能重）
      groups.each_value do |items|
        supplier = items.first.mes_supplier
        head = HEADERS[supplier&.bill_entity] || HEADERS['wintouch'] # 该供应商的抬头/税口径
        name = supplier&.name.presence || '未指定供应商'
        used[name] += 1
        suffix = used[name] > 1 ? "-#{used[name]}" : ''
        zip.put_next_entry("#{sanitize(name)}#{suffix}.csv")
        zip.write("﻿#{supplier_doc(supplier, items, head)}") # BOM：Excel 认 UTF-8
      end
    end
    buffer.rewind
    buffer
  end

  private

  # 按供应商分组（保序）；无供应商的料归到 nil 组由抬头回落 wintouch。
  def grouped
    @po.purchase_items
       .includes(:mes_material, :crm_product, :mes_supplier)
       .group_by(&:mes_supplier_id)
  end

  def supplier_payload(items)
    supplier = items.first.mes_supplier
    head = HEADERS[supplier&.bill_entity] || HEADERS['wintouch']
    rows = items.each_with_index.map { |item, i| item_payload(item, i + 1, head) }
    {
      name: supplier&.name.presence || '未指定供应商',
      contact_name: supplier&.contact_name,
      address: supplier&.address,
      bill_entity: supplier&.bill_entity || 'wintouch',
      company: head[:company],
      title: head[:title],
      taxed: head[:taxed],
      currency: head[:currency],
      items: rows,
      total_qty: rows.sum { |r| r[:qty] },
      total_amount: rows.sum { |r| r[:amount] }.round(2)
    }
  end

  def item_payload(item, idx, head)
    qty = item.qty.to_f
    price = unit_price(item, head).round(2)
    { index: idx, code: code(item), name: name(item), spec: spec(item),
      unit: item.unit, qty: qty, price: price, amount: (qty * price).round(2), remark: item.remark }
  end

  def supplier_doc(supplier, items, head)
    CSV.generate do |csv|
      header_rows(csv, supplier, head)
      item_rows(csv, items, head)
    end
  end

  def header_rows(csv, supplier, head)
    csv << [head[:company]]
    csv << [head[:title]]
    csv << ['供应商', supplier&.name, '', '采购单号', @po.po_no]
    csv << ['联系人', supplier&.contact_name, '', '采购日期', @po.created_at&.to_date&.to_s]
    csv << ['地址', supplier&.address, '', '币别', head[:currency]]
    csv << []
    csv << ['序号', '我司料号', '产品名称', '规格', '单位', '数量',
            head[:taxed] ? '含税单价' : '未税单价', head[:taxed] ? '含税金额' : '未税金额', '备注']
  end

  def item_rows(csv, items, head)
    total_qty = total_amt = 0.to_d
    items.each_with_index do |item, i|
      qty = item.qty.to_d
      price = unit_price(item, head)
      amt = (qty * price).round(2)
      total_qty += qty
      total_amt += amt
      csv << [i + 1, code(item), name(item), spec(item), item.unit, fmt(qty), fmt(price), fmt(amt), item.remark]
    end
    csv << ['', '', '', '', '合计', fmt(total_qty), '', fmt(total_amt), '']
  end

  # 单价：采购单存的是未税价（rate_micros）；含税抬头 × 1.13。
  def unit_price(item, head)
    net = (item.rate_micros || 0) / 1_000_000.0
    head[:taxed] ? net * TAX_RATE : net
  end

  def code(item) = item.item_type == 'PRODUCT' ? item.crm_product&.sku : item.mes_material&.material_no
  def name(item) = item.item_type == 'PRODUCT' ? item.crm_product&.name : item.mes_material&.name
  def spec(item) = item.item_type == 'PRODUCT' ? nil : item.mes_material&.specification
  def fmt(num) = format('%g', num.to_f)
  def sanitize(str) = str.to_s.gsub(%r{[/\\:*?"<>|]}, '_')
end
