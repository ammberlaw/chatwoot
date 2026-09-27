
# 采购单按供应商拆分导出：一张采购单里各供应商的料各成一份，打包成 zip、直接转发给对应供应商。
# 每份只含该供应商的物料，绝不带其他供应商 / 关联生产订单 / 成本毛利。
# 抬头/税口径按【每个供应商档案上的 bill_entity】自动选（同一张单可含税、未税供应商混排）。
#
# 产物是公司原始 .xlsx 模板 1:1 填充（Mes::PoTemplateFiller，照 Crm::PiTemplateFiller 那套 rubyzip 改 XML）：
# liontek → 联迪含税采购合同（含公章）；其它/nil → 深圳联合触控未税采购订单。
class Mes::PoSupplierExport
  # 开票主体（抬头）：决定公司名 / 单据名 / 税口径。取自供应商档案 bill_entity。
  HEADERS = {
    'wintouch' => { company: '深圳联合触控科技有限公司', title: '采购订单', taxed: false, currency: '不含税 RMB' },
    'liontek' => { company: '东莞市联迪科技有限公司', title: '采购合同', taxed: true, currency: '含税 RMB' }
  }.freeze
  TAX_RATE = 1.13 # 联迪含税 13%：未税价 × 1.13 = 含税价

  def initialize(purchase_order, supplier_ids: nil)
    @po = purchase_order
    @supplier_ids = Array(supplier_ids).presence
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

  # 按供应商导出 PDF：每家填公司原始 .xlsx 模板（含公章）→ Gotenberg 转 1:1 PDF。
  # 单个供应商直接返回 PDF；多个供应商打包成 zip（每家一份 PDF）。
  # 返回 { filename:, content_type:, io: }（供 controller send_data）。
  # 导出 PDF。多家供应商时合成**一个** PDF（每家一页），不再打 zip——
  # 原来 11 家就是 11 个文件打包，下载完还要解压、一个个开，发群前还得挑。
  def to_pdf_download
    sheets = grouped.values.map do |items|
      supplier = items.first.mes_supplier
      name = supplier&.name.presence || '未指定供应商'
      xlsx = Mes::PoTemplateFiller.new(supplier: supplier, items: items, purchase_order: @po).to_stream.read
      [name, xlsx]
    end
    raise ArgumentError, '没有可导出的供应商' if sheets.empty?

    pdf = Mes::GotenbergClient.office_to_pdf_merged(sheets.map { |name, xlsx| ["#{sanitize(name)}.xlsx", xlsx] })
    suffix = sheets.size == 1 ? sanitize(sheets.first[0]) : "#{sheets.size}家供应商"
    { filename: "采购单-#{@po.po_no}-#{suffix}.pdf", content_type: 'application/pdf', io: StringIO.new(pdf) }
  end

  # 返回打包好的 zip（每供应商一个 .xlsx，填公司原始模板）IO 流。
  def to_zip_stream
    buffer = Zip::OutputStream.write_buffer do |zip|
      used = Hash.new(0) # 供应商同名去重（文件名不能重）
      grouped.each_value do |items|
        supplier = items.first.mes_supplier
        name = supplier&.name.presence || '未指定供应商'
        used[name] += 1
        suffix = used[name] > 1 ? "-#{used[name]}" : ''
        zip.put_next_entry("#{sanitize(name)}#{suffix}.xlsx")
        doc = Mes::PoTemplateFiller.new(supplier: supplier, items: items, purchase_order: @po).to_stream
        zip.write(doc.read)
      end
    end
    buffer.rewind
    buffer
  end

  private

  # 把每家 PDF 打包成 zip（同名供应商加序号后缀避免文件名冲突）。
  # 按供应商分组（保序）；无供应商的料归到 nil 组由抬头回落 wintouch。
  # 按供应商分组；给了 supplier_ids 就只取这几家（导出时勾选用）。
  # 「未指定供应商」那组的 key 是 nil，前端用 0 表示，这里换算回来。
  def grouped
    all = @po.purchase_items
             .includes(:mes_material, :crm_product, :mes_supplier)
             .group_by(&:mes_supplier_id)
    return all if @supplier_ids.blank?

    wanted = @supplier_ids.map { |id| id.to_i.zero? ? nil : id.to_i }
    all.slice(*wanted)
  end

  def supplier_payload(items)
    supplier = items.first.mes_supplier
    head = HEADERS[supplier&.bill_entity] || HEADERS['wintouch']
    rows = items.each_with_index.map { |item, i| item_payload(item, i + 1, head) }
    {
      # 前端勾选导出用；「未指定供应商」没有 id，统一用 0。
      supplier_id: supplier&.id || 0,
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

  # 单价（payload 前端预览用）：采购单存的是未税价（rate_micros）；含税抬头 × 1.13。
  # zip 导出走 Mes::PoTemplateFiller，取模型换算好的 untaxed/taxed micros，不用此估算。
  def unit_price(item, head)
    net = (item.rate_micros || 0) / 1_000_000.0
    head[:taxed] ? net * TAX_RATE : net
  end

  # 料号/名称/规格：统一取产品档案(crm_product，物料与外购成品都走它)，旧数据回落 mes_material。
  def code(item) = item.crm_product&.sku || item.mes_material&.material_no
  def name(item) = item.crm_product&.name || item.mes_material&.name
  def spec(item) = item.crm_product&.specification || item.mes_material&.specification
  def sanitize(str) = str.to_s.gsub(%r{[/\\:*?"<>|]}, '_')
end
