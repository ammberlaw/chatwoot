# 报价单 / PI 发出前的体检。
#
# 为什么要有：AI 自己建单时会主动核历史价（实测它拦过「报 48.5、这家历史成交 79」
# 和「上次是 EUR、这次写成 USD」），但**手工建的单没人管**——生产里 183 张 PI、
# 19 张报价单，绝大多数是人敲的。发出去才发现少打一位数，就得跟客户重新谈。
#
# 刻意**不调模型**：这些全是能算死的对比（算术、缺字段、和历史价差多少），
# 让模型重做一遍既慢又可能把数字说错，还每次都要花钱。
#
# ⚠️ 只看售价口径。产品档案上的 cost_price_micros（成本价）一个字都不许碰——
# 销售端不可见成本，体检结果是给业务员看的。
class Crm::DocHealthCheck
  Finding = Struct.new(:level, :title, :detail, keyword_init: true)

  # 和历史价差多少才值得提醒。差一点点是正常议价，差一半多半是打错了。
  PRICE_GAP = 0.30
  # 金额自洽允许的误差：单价存的是 micros，按量乘出来会有舍入尾差。
  ROUNDING_SLACK = 100 # micros，即 0.0001 元

  def self.for_pi(pi) = new(doc: pi, kind: :pi).call
  def self.for_quote(quote) = new(doc: quote, kind: :quote).call

  def initialize(doc:, kind:)
    @doc = doc
    @kind = kind
    @findings = []
  end

  def call
    check_arithmetic
    check_terms if @kind == :pi
    check_currency
    check_prices
    @findings
  end

  private

  def account = @doc.account
  def currency = (@kind == :pi ? @doc.currency : @doc.quote_currency).presence || 'USD'

  def rows
    @rows ||= (@kind == :pi ? @doc.pi_items : @doc.line_items).map do |it|
      { model: (@kind == :pi ? it.model : it.name).to_s.strip,
        desc: (@kind == :pi ? it.description : it.product_name_snapshot).to_s.strip,
        qty: it.quantity.to_d, unit: it.unit_price_micros.to_i, amount: it.amount_micros.to_i }
    end
  end

  # ① 算术：每行金额 = 数量 × 单价；合计 = 各行之和。
  # 这条抓的是「改了数量忘了改金额」「导出模板里合计写死了」这类——
  # 单子上两个数自己打架，客户一眼就看出来。
  def check_arithmetic
    rows.each_with_index do |r, i|
      expect = (r[:qty] * r[:unit]).round
      next if (expect - r[:amount]).abs <= ROUNDING_SLACK

      @findings << Finding.new(level: 'warn', title: "第 #{i + 1} 行金额对不上",
                               detail: "#{r[:model]}：#{fnum(r[:qty])} × #{money(r[:unit])} 应为 #{money(expect)}，" \
                                       "单子上写的是 #{money(r[:amount])}")
    end
    check_total
  end

  # 合计口径必须照各自单据自己的算法来，不能简单拿明细相加去比——
  # PI 的合计含运费（Crm::Pi 第 104 行：items_sum + shipping_cost_micros），
  # 报价单还要减折扣、加运费和税（QuotesController#recalc_totals）。
  # 第一版漏了运费，拿真实单子一测就误报「各行 1,740、合计 2,686」，
  # 而那 946 正是运费。体检误报比不报更糟——报错一次，以后没人再信它。
  def check_total
    return if rows.empty?

    sum = rows.sum { |r| r[:amount] }
    expect = sum + extras
    total = @doc.total_amount_micros.to_i
    return if (expect - total).abs <= ROUNDING_SLACK

    @findings << Finding.new(level: 'warn', title: '合计对不上',
                             detail: "明细 #{money(sum)}#{extras_text}，应为 #{money(expect)}，" \
                                     "单子上的合计是 #{money(total)}")
  end

  def extras
    if @kind == :pi
      @doc.shipping_cost_micros.to_i
    else
      -@doc.discount_amount_micros.to_i + @doc.shipping_fee_micros.to_i + @doc.tax_amount_micros.to_i
    end
  end

  # 把「明细之外还加减了什么」摆出来，否则用户只看到两个数不等、不知道差在哪。
  def extras_text
    parts = if @kind == :pi
              [['运费', @doc.shipping_cost_micros.to_i]]
            else
              [['折扣', -@doc.discount_amount_micros.to_i], ['运费', @doc.shipping_fee_micros.to_i],
               ['税', @doc.tax_amount_micros.to_i]]
            end
    shown = parts.reject { |(_, v)| v.zero? }
                 .map { |(label, v)| "#{v.negative? ? '-' : '+'}#{label} #{money(v.abs)}" }
    shown.empty? ? '' : " #{shown.join(' ')}"
  end

  # ② PI 的条款和物流字段：AI 建的 PI 这几栏本来就是空的（它只填客户和明细），
  # 人工建的也常漏。空着导出去，客户收到一张没有付款方式和港口的 PI。
  # 哪几栏算「该填没填」，是按生产 183 张 PI 的实际填写率定的，不是照单据模板抄的：
  #   付款条款 缺 3 张 / 起运港 0 / 原产地 0 / 目的港 18 / 运输方式 26  → 都是常规必填，缺了就报
  #   买方地址 缺 93 张（一半）                                      → 他们流程里本来就不强制
  # 把买方地址也报成警告的话，一半的单子都会弹一条——体检一旦变成噪音就没人看了，
  # 所以它单独降成提示级。
  PI_REQUIRED = {
    terms: '付款条款', port_of_shipment: '起运港', port_of_destination: '目的港',
    shipping_method: '运输方式', country_of_origin: '原产地'
  }.freeze
  PI_OPTIONAL = { buyer_address: '买方地址', buyer_tel: '买方电话' }.freeze

  def check_terms
    missing = PI_REQUIRED.filter_map { |field, label| label if blank_field?(field) }
    @findings << Finding.new(level: 'warn', title: '这几栏还空着', detail: missing.join('、')) if missing.any?

    optional = PI_OPTIONAL.filter_map { |field, label| label if blank_field?(field) }
    return if optional.empty?

    @findings << Finding.new(level: 'info', title: '这几栏也空着（非必填）', detail: optional.join('、'))
  end

  def blank_field?(field)
    @doc.public_send(field).to_s.strip.blank?
  end

  # ③ 币种：和这家客户上一次成交/报价的币种不一样就提醒。
  # 实测 AI 拦过一次「这家 8 月成交价是 EUR 128，这次写成 USD」——
  # 币种错了价格再对也是错的，而且一眼看不出来。
  def check_currency
    return if @doc.crm_customer_id.blank?

    last = account.crm_pis.where(crm_customer_id: @doc.crm_customer_id)
                  .where.not(id: @doc.id).where.not(currency: [nil, ''])
                  .order(pi_date: :desc, id: :desc).first
    return if last.nil? || last.currency == currency

    @findings << Finding.new(level: 'warn', title: '币种和这家客户以往不同',
                             detail: "这张是 #{currency}，上一张 #{last.pi_no} 是 #{last.currency}（#{last.pi_date&.to_date}）")
  end

  # ④ 单价对比：先比这家客户的历史价，没有就比档案挂牌售价。
  # 只在同币种之间比——跨币种比大小是在比汇率，没有意义。
  def check_prices
    rows.each do |r|
      next if r[:model].blank? || r[:unit] <= 0

      hist = history_price(r[:model])
      next compare(r, hist[:price], "这家客户 #{hist[:label]}") if hist

      listed = listed_price(r[:model])
      compare(r, listed, '产品档案挂牌售价') if listed
    end
  end

  # 这家客户以前买过/报过同型号的最近一次单价（同币种）。
  def history_price(model)
    account.crm_pis.where(crm_customer_id: @doc.crm_customer_id, currency: currency)
           .where.not(id: @doc.id).includes(:pi_items)
           .order(pi_date: :desc, id: :desc).limit(40).each do |doc|
      hit = doc.pi_items.find { |it| it.model.to_s.strip.casecmp?(model) && it.unit_price_micros.to_i.positive? }
      return { price: hit.unit_price_micros.to_i, label: "#{doc.pi_no}（#{doc.pi_date&.to_date}）" } if hit
    end
    nil
  end

  # 产品档案的挂牌售价。⚠️ 只取 sale_price_micros，绝不碰 cost_price_micros。
  def listed_price(model)
    p = account.crm_products.where('sku ILIKE :m OR name ILIKE :m', m: model).first
    price = p&.sale_price_micros.to_i
    price.positive? ? price : nil
  end

  def compare(row, ref, label)
    return if ref.to_i <= 0

    gap = (row[:unit] - ref).abs / ref.to_f
    return if gap < PRICE_GAP

    direction = row[:unit] < ref ? '低于' : '高于'
    @findings << Finding.new(
      level: 'warn', title: "#{row[:model]} 单价#{direction}#{label} #{(gap * 100).round}%",
      detail: "这次 #{money(row[:unit])}，#{label} #{money(ref)}"
    )
  end

  def money(micros)
    "#{currency} #{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', micros.to_i / 1e6))}"
  end

  def fnum(v)
    d = v.to_d
    d == d.to_i ? d.to_i.to_s : d.to_s('F')
  end
end
