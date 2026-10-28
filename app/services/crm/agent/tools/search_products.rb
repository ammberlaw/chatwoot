# 产品档案查询。做报价/PI 时模型需要知道「这个型号叫什么、规格是什么、挂的售价多少」。
#
# 成本价不给模型——它会出现在对话里，而对话是业务员在看（生态硬约束：销售端不可见成本）。
#
# 查法走 Crm::Agent::ProductMatch 的五级放宽：精确编码 → 原样包含 → 去分隔符包含 →
# 拆词全中 → 拆词任一中。**命中哪一级决定怎么说话**：精确的可以直接报编码，
# 靠拆词猜出来的必须讲明是按哪个词猜的——不讲清楚，模型会把「欧规充电器」
# 当成「欧规电源线」的确定答案报给客户。
class Crm::Agent::Tools::SearchProducts < Crm::Agent::Tools::Base
  description '查产品档案：按编码、名称或规格搜。用来做报价单或 PI 时确认型号、规格和售价。' \
              '编码带不带横杠都行（K705-A 和 K705A 一样）。' \
              '完全搜不到时会退一步给出最接近的几条并注明是猜的——这种时候别当成确定答案，' \
              '先问用户是不是指其中某一个。'
  param :keyword, desc: '产品编码、名称或规格关键词'
  param :limit, type: 'integer', desc: '最多返回几条，默认 10', required: false

  # 每一级该怎么开口。空串＝有把握，直接列结果就行。
  TIER_NOTE = {
    exact: '',
    contains: '',
    normalized: '',
    ranked: '**档案里没有完全叫「%<kw>s」的东西。**下面是把它拆成「%<term>s」之后、' \
            '按命中片段数排出来的最接近几条（最高命中 %<rate>s）。' \
            '命中越少越不可靠——先把这几条摆给用户让他认，别直接当成答案写进报价单或 PI。'
  }.freeze

  def execute(keyword:, limit: 10)
    rows = scope.account.crm_products.where(is_active: true)
    result = Crm::Agent::ProductMatch.new(rows).call(keyword, limit: limit)
    return miss(keyword) if result.rows.empty?

    [note(result, keyword), result.rows.map { |p| line(p) }.join("\n")].reject(&:blank?).join("\n")
  end

  private

  def note(result, keyword)
    tpl = TIER_NOTE[result.tier].to_s
    return '' if tpl.blank?

    format(tpl, term: result.matched_term, kw: keyword, rate: result.hit_rate)
  end

  # 连拆词都捞不到才算真没有。这里也要给出路，不能只说「没搜到」——
  # 业务员收到这句话只会换个词再问一遍（生产上「欧规电源线」就被问了三遍）。
  def miss(keyword)
    "产品档案里搜不到「#{keyword}」，换个说法也没找到。" \
      '请让用户换一个更接近档案里写法的词（比如用品类名「充电器」「显示器」而不是口语说法），' \
      '或者直接给商品编码。'
  end

  def line(product)
    "#{product.sku}｜#{product.name}｜规格 #{product.specification.presence || '—'}｜" \
      "单位 #{product.unit.presence || '—'}｜售价 #{money(product.sale_price_micros, product.pricing_currency.presence || 'CNY')}"
  end
end
