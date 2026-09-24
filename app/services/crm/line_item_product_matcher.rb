# 明细文字 → 产品档案 的匹配。转单弹窗与订单/PI 录入共用同一套口径。
#
# 原来的做法只按产品名精确匹配、命中多条就放弃，实测近 60 天 199 行明细里
# 只有 22 行能自动带出（11%）：
#   · 53 行命中多条（档案里 560 个名字重复，「863主板」就有 42 条）
#   · 114 行查无此物（PI 上是英文自由描述）
#   · 10 行是运费（本来就不是产品）
#
# 现在按可靠性分层：记忆 > 编码精确 > 名称精确 > 编码/名称/规格模糊。
# 拿不准就不猜，但把候选带回去让人一次点中——而不是留空让人从四千多条里重搜。
class Crm::LineItemProductMatcher
  CANDIDATE_LIMIT = 6
  # 运费/杂费行永远匹配不到产品，标出来让前端默认跳过，不占用「必须选产品」的名额。
  FEE_PATTERN = /freight|delivery|shipping|postage|运费|快递|物流费|fee\b/i

  def initialize(account)
    @account = account
  end

  # texts: 明细文字数组。返回 { 原文 => { product:, candidates:, source:, fee: } }
  def match_all(texts)
    list = Array(texts).map(&:to_s)
    aliases = Crm::ProductAlias.lookup(account: @account, texts: list)
    by_id = products_by_id(aliases.values)
    list.index_with { |text| match_one(text, aliases, by_id) }
  end

  private

  def products_by_id(ids)
    return {} if ids.blank?

    @account.crm_products.where(id: ids.uniq).index_by(&:id)
  end

  def match_one(text, aliases, by_id)
    return { product: nil, candidates: [], source: 'fee', fee: true } if fee_line?(text)

    key = Crm::ProductAlias.normalize(text)
    return { product: nil, candidates: [], source: 'blank', fee: false } if key.blank?

    remembered = by_id[aliases[key]]
    return { product: remembered, candidates: [], source: 'memory', fee: false } if remembered

    resolve(key)
  end

  def fee_line?(text)
    text.to_s.match?(FEE_PATTERN)
  end

  # 精确优先、模糊兜底；唯一才算命中，多条一律回候选。
  def resolve(key)
    %i[sku_exact name_exact fuzzy].each do |strategy|
      hits = send(strategy, key)
      next if hits.empty?
      return { product: hits.first, candidates: [], source: strategy.to_s, fee: false } if hits.size == 1

      return { product: nil, candidates: hits.first(CANDIDATE_LIMIT), source: "#{strategy}_multi", fee: false }
    end
    { product: nil, candidates: [], source: 'none', fee: false }
  end

  def sku_exact(key)
    squished(:sku).where("REPLACE(LOWER(sku), ' ', '') = ?", key).limit(CANDIDATE_LIMIT + 1).to_a
  end

  def name_exact(key)
    squished(:name).where("REPLACE(LOWER(name), ' ', '') = ?", key).limit(CANDIDATE_LIMIT + 1).to_a
  end

  # 编码/名称/规格任一包含即算候选。规格里常藏着型号（WT430ZD-C 这类）。
  def fuzzy(key)
    like = "%#{key}%"
    @account.crm_products.where(
      "REPLACE(LOWER(sku), ' ', '') LIKE :q OR REPLACE(LOWER(name), ' ', '') LIKE :q " \
      "OR REPLACE(LOWER(specification), ' ', '') LIKE :q", q: like
    ).limit(CANDIDATE_LIMIT + 1).to_a
  end

  def squished(_column)
    @account.crm_products
  end
end
