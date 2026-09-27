# 采购单按供应商拆分导出：一张采购单里各供应商的料各成一份，合成一个 PDF（每家一页），直接转发给供应商。
# 每份只含该供应商的物料，绝不带其他供应商 / 关联生产订单 / 成本毛利。
# 抬头/税口径默认按【每个供应商档案上的 bill_entity】自动选（同一张单可含税、未税供应商混排），
# 前端可传 bill_entities 临时改某家的抬头（只影响这次出的单）。
#
# 产物是公司原始 .xlsx 模板 1:1 填充（Mes::PoTemplateFiller，照 Crm::PiTemplateFiller 那套 rubyzip 改 XML）：
# liontek → 联迪含税采购合同（含公章）；其它/nil → 深圳联合触控未税采购订单。
class Mes::PoSupplierExport
  # 开票主体（抬头）：决定公司名 / 单据名 / 税口径。取自供应商档案 bill_entity。
  HEADERS = {
    'wintouch' => { company: '深圳联合触控科技有限公司', title: '采购订单', taxed: false, currency: '不含税 RMB' },
    'liontek' => { company: '东莞市联迪科技有限公司', title: '采购合同', taxed: true, currency: '含税 RMB' }
  }.freeze

  # bill_entities: { supplier_id => 'wintouch'|'liontek' } —— 导出/预览时手动改抬头，
  # 只影响这一次出的单，不动供应商档案（「未指定供应商」那组 key 用 0）。
  def initialize(purchase_order, supplier_ids: nil, bill_entities: nil)
    @po = purchase_order
    @supplier_ids = Array(supplier_ids).presence
    @bill_entities = normalize_entities(bill_entities)
  end

  # 按供应商分组的结构化数据（供前端列出供应商、勾选与改抬头；价按抬头口径算好）。
  # 价按抬头口径算好（联迪含税 = 未税 ×1.13），前端只渲染不计算；绝不含成本/毛利/其他供应商。
  def payload
    {
      po_no: @po.po_no,
      date: @po.created_at&.to_date&.to_s,
      delivery_date: @po.delivery_date&.to_s,
      suppliers: grouped.map { |_id, items| supplier_payload(items) }
    }
  end

  # 按供应商导出 PDF：每家填公司原始 .xlsx 模板（含公章）→ Gotenberg 转 1:1 PDF，
  # 多家合成**一个** PDF（每家一页），不再打 zip——原来 11 家就是 11 个文件打包，
  # 下载完还要解压、一个个开，发群前还得挑。
  # 返回 { filename:, content_type:, io: }（供 controller send_data）。
  def to_pdf_download
    sheets = grouped.values.map do |items|
      supplier = items.first.mes_supplier
      name = supplier&.name.presence || '未指定供应商'
      xlsx = Mes::PoTemplateFiller.new(supplier: supplier, items: items, purchase_order: @po,
                                       bill_entity: entity_for(supplier)).to_stream.read
      [name, xlsx]
    end
    raise ArgumentError, '没有可导出的供应商' if sheets.empty?

    pdf = Mes::GotenbergClient.office_to_pdf_merged(ordered_sheet_names(sheets))
    suffix = sheets.size == 1 ? sanitize(sheets.first[0]) : "#{sheets.size}家供应商"
    { filename: "采购单-#{@po.po_no}-#{suffix}.pdf", content_type: 'application/pdf', io: StringIO.new(pdf) }
  end

  private

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
    entity = entity_for(supplier)
    head = HEADERS[entity]
    rows = items.each_with_index.map { |item, i| item_payload(item, i + 1, head) }
    {
      # 前端勾选导出用；「未指定供应商」没有 id，统一用 0。
      supplier_id: supplier&.id || 0,
      name: supplier&.name.presence || '未指定供应商',
      contact_name: supplier&.contact_name,
      address: supplier&.address,
      bill_entity: entity,
      # 档案上的原始抬头：前端要能看出「这次是手动改过的」。
      default_bill_entity: default_entity(supplier),
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
    qty = item.qty.to_d
    price = unit_price(item, head)
    { index: idx, code: code(item), name: name(item), spec: spec(item),
      unit: item.unit, qty: qty.to_f, price: price.to_f, amount: (qty * price).round(2).to_f, remark: item.remark }
  end

  # 与 PDF 共用模型税价换算；先按完整单价算行金额，再四舍五入到分。
  def unit_price(item, head)
    micros = head[:taxed] ? item.taxed_rate_micros : item.untaxed_rate_micros
    micros.to_d / 1_000_000
  end

  # 料号/名称/规格：统一取产品档案(crm_product，物料与外购成品都走它)，旧数据回落 mes_material。
  def code(item) = item.crm_product&.sku || item.mes_material&.material_no
  def name(item) = item.crm_product&.name || item.mes_material&.name
  def spec(item) = item.crm_product&.specification || item.mes_material&.specification

  # Gotenberg 合并时按**文件名字母序**排，不按传入顺序——不加前缀的话 PDF 里的页序
  # 和预览里列的供应商顺序对不上。补两位序号前缀钉死顺序。
  def ordered_sheet_names(sheets)
    sheets.each_with_index.map do |(name, xlsx), i|
      [format('%<idx>02d-%<name>s.xlsx', idx: i + 1, name: sanitize(name)), xlsx]
    end
  end

  def default_entity(supplier) = HEADERS.key?(supplier&.bill_entity) ? supplier.bill_entity : 'wintouch'

  # 这次出单用哪个抬头：前端传了就用前端的，没传就用档案上的。
  def entity_for(supplier)
    @bill_entities[supplier&.id || 0] || default_entity(supplier)
  end

  # { '13' => 'liontek' } / { 13 => 'liontek' } 都收；非法主体直接忽略，回落档案值。
  def normalize_entities(raw)
    return {} if raw.blank?

    raw.to_h.each_with_object({}) do |(id, entity), acc|
      acc[id.to_i] = entity.to_s if HEADERS.key?(entity.to_s)
    end
  end

  def sanitize(str) = str.to_s.gsub(%r{[/\\:*?"<>|]}, '_')
end
