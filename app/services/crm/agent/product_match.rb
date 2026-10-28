# 产品档案「查得准」的那一层：逐级放宽地找，找不到也不空手而归。
#
# 为什么要有这一层：原来 search_products 就是一句 `ILIKE '%关键词%'`，查不到直接回
# 「没搜到」。生产上最近 15 个提问里有 5 个是同一件事换着说法问了两三遍——
#   · 「欧规电源线编码」→「欧规线海关编码」→「欧规电源线的商品编码」
#   · 「K705A的商品编码」→「K705-A的商品编码」
# 前者库里压根没有「电源线」这个词，只有「欧规充电器」（P.13.001~008 八个同名）；
# 后者库里是 `K705A`，带横杠就匹配不上。两次都是业务员在替系统试错。
#
# 分五级，命中哪一级就停在哪一级，并把级别告诉调用方——因为**话术要跟着变**：
# 精确命中可以直接报编码，靠拆词猜出来的必须说明是猜的，不然模型会把
# 「欧规充电器」当成「欧规电源线」的确定答案报给客户。
class Crm::Agent::ProductMatch
  Result = Struct.new(:rows, :tier, :matched_term, :hit_rate, keyword_init: true)

  # 编码归一：只留字母数字再比。K705-A / K705 A / k705a / K705.A 在库里都是同一个 K705A。
  #
  # ⚠️ SQL 里**不能写 POSIX 字符类**（[[:space:]]）：Rails 的具名绑定会把 `:space`
  # 当成占位符，报 missing value for :space。直接按「非字母数字」剔除，顺带比列分隔符更稳。
  # 中文名归一后是空串，所以这一级天然只对编码生效——正是想要的。
  SEPARATORS = /[^A-Za-z0-9]+/
  NORM_SQL = "UPPER(REGEXP_REPLACE(%<col>s, '[^A-Za-z0-9]', '', 'g'))".freeze

  # 中文没有空格可切，按 2 字滑窗拆（欧规电源线 → 欧规·规电·电源·源线）。
  # 2 字是外贸品名里最小的有意义单位（欧规/美规/充电/显示/触摸/电容…），
  # 拆成单字会把「线」这种到处都是的字也拿去匹配，噪音盖过信号。
  CJK_GRAM = 2
  # 「的」「是」这类拆出来只会制造噪音。不做完整停用词表——外贸品名里就这几个。
  NOISE = %w[的 和 与 及 或 个 是 有 要 请 帮 查].freeze

  # 猜出来的最多摆这么多条：再多业务员也懒得认。
  MAX_LOOSE = 8

  def initialize(relation)
    @relation = relation
  end

  # tier 说明（话术按它分档）：
  #   :exact      编码归一后完全相等 —— 就是这个，直接报
  #   :contains   原样包含（今天的行为）—— 有把握
  #   :normalized 去掉分隔符后包含 —— 有把握
  #   :ranked     拆词后按**命中了几个片段**排序 —— 猜的，命中率要报给模型让它自己掂量
  def call(keyword, limit: 10)
    kw = keyword.to_s.strip
    return Result.new(rows: [], tier: :none) if kw.blank?

    cap = [limit.to_i.positive? ? limit.to_i : 10, 25].min
    exact(kw) || contains(kw, cap) || normalized(kw, cap) || by_terms(kw, cap) || Result.new(rows: [], tier: :none)
  end

  private

  attr_reader :relation

  def norm(text) = text.to_s.upcase.gsub(SEPARATORS, '')

  def exact(word)
    rows = relation.where("#{format(NORM_SQL, col: 'crm_products.sku')} = :k", k: norm(word)).limit(5).to_a
    rows.any? ? Result.new(rows: rows, tier: :exact, matched_term: word) : nil
  end

  def contains(word, cap)
    rows = relation.where(
      'crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t',
      t: "%#{word}%"
    ).order(:sku).limit(cap).to_a
    rows.any? ? Result.new(rows: rows, tier: :contains, matched_term: word) : nil
  end

  def normalized(word, cap)
    n = norm(word)
    return nil if n.blank?

    rows = relation.where(
      "#{format(NORM_SQL, col: 'crm_products.sku')} LIKE :t OR #{format(NORM_SQL, col: 'crm_products.name')} LIKE :t",
      t: "%#{n}%"
    ).order(:sku).limit(cap).to_a
    rows.any? ? Result.new(rows: rows, tier: :normalized, matched_term: word) : nil
  end

  # 拆词后按「命中了几个片段」排序。
  #
  # 为什么不是「全部片段都要命中」：生产上那位业务员要的「欧规电源线」，库里写的是
  # **欧规三插电源线**——中间插了「三插」两个字，整串 ILIKE 匹配不上，
  # 2 字滑窗里的「规电」也不存在。但它命中了 欧规+电源+源线 三个片段，
  # 而「欧规充电器」只命中 欧规 一个。按命中数排，对的那条自己就浮到最前面。
  def by_terms(word, cap)
    terms = split_terms(word)
    return nil if terms.empty?

    args = terms.map { |term| "%#{term}%" }
    # select 不走绑定参数，得自己 sanitize——直接插值等于开 SQL 注入的口子
    # （关键词是模型从用户那句话里抄过来的，不能当可信输入）。
    score = ActiveRecord::Base.sanitize_sql_array(
      [terms.map { 'CASE WHEN crm_products.name ILIKE ? THEN 1 ELSE 0 END' }.join(' + '), *args]
    )
    rows = relation
           .select("crm_products.*, (#{score}) AS term_hits")
           .where(terms.map { 'crm_products.name ILIKE ?' }.join(' OR '), *args)
           .order(Arel.sql('term_hits DESC, crm_products.sku'))
           .limit([cap, MAX_LOOSE].min)
           .to_a
    return nil if rows.empty?

    Result.new(rows: rows, tier: :ranked, matched_term: terms.join('·'), hit_rate: hit_rate(rows, terms))
  end

  # 最好那条命中了几个片段 / 一共几个片段。模型据此判断这次猜得有多准。
  def hit_rate(rows, terms)
    "#{rows.first.try(:term_hits) || 1}/#{terms.size}"
  end

  # ASCII 按非字母数字切；中文按 2 字滑窗。两段混排（「K705 外壳」）各切各的。
  def split_terms(word)
    ascii = word.scan(/[A-Za-z0-9]{2,}/)
    cjk = word.scan(/\p{Han}+/).flat_map { |run| grams(run) }
    (ascii + cjk).uniq.reject { |t| NOISE.include?(t) }
  end

  def grams(run)
    return [run] if run.length <= CJK_GRAM

    (0..run.length - CJK_GRAM).map { |i| run[i, CJK_GRAM] }.reject { |g| NOISE.any? { |n| g.include?(n) } }
  end
end
