# 把人／模型写的搜索词，翻译成 Apollo 真实存在的业务标签。
#
# 为什么非要这一层：**Apollo 的关键词标签是一套固定词表，不是全文检索。**
# 整句当一个标签去搜，词表里没有就是 0 条：
#   "own brand consumer electronics" → 0      "white label tablet" → 0
#   "consumer electronics"           → 有     "kids tablet"        → 有（美国 5 家）
#
# 2026-11-08 之前的做法是把整句按空格拆成多个标签丢进去，而 Apollo 对多标签取**并集**：
# "consumer electronics brand" 变成 consumer ∪ electronics ∪ brand = 两万多家，
# 捞回来的是行业杂志、广告代理、设计奖项、招聘猎头——一家买家都没有。
# 德国市场那一轮 32 家「consumer electronics brand」里 0 家通过初筛，就是这么来的。
#
# 所以这里只做一件事：**找出真的在词表里的那个标签，找不到就认账，不硬凑。**
class Crm::ApolloTagResolver
  # 退一步时词组最少剩几个词。
  MIN_FALLBACK_WORDS = 2
  # 退出来的词组至少要挂这么多家公司才算数。
  # 词表里确实存在但只挂着一两家的标签（"games wholesaler" 全球 1 家）等于没有，
  # 认了它就等于把这个搜索词废掉——继续往下退，退到品类词反而有用
  # （"toys and games wholesaler" 退到 toys 是六千多家真玩具公司）。
  MIN_FALLBACK_TOTAL = 10
  # 单个词挂着比这还多的公司，那就不是品类而是一整个大行业了（"games" 全球 18 万家，
  # 把电竞、手游、桌游全算进来），搜它等于没筛。
  SINGLE_WORD_MAX = 50_000
  # 连词组都退不出来时，才退到单个词——而且**只退品类词**。
  # 下面这些是修饰语和万金油：单独拿去搜 brand 回来的是广告代理、搜 wholesaler
  # 回来的是卖任何东西的批发商，一点指向性都没有。品类词（toys / tablets /
  # spielwaren / juguetes）不在这个名单里，它们单独搜是有意义的——
  # 「toys and games wholesaler」这个词真正值钱的部分就是 toys。
  GENERIC_WORDS = %w[
    and for the of or own white private label brand branded consumer consumers
    retail wholesale wholesaler wholesalers distributor distributors distribution
    supplier suppliers vendor buyer buyers buying group chain store stores shop
    company companies business technology technologies solutions services
    products product goods trading import export online global international
    manufacturer manufacturing specialist specialists market markets
  ].to_set.freeze
  # 一个词最多探几次。探测不扣 credits，而且按词缓存（跟市场无关），
  # 一轮任务 12 个词也就几十次。
  MAX_PROBES = 6
  # 探测失败后重试前等多久。
  RETRY_WAIT = 1

  Result = Struct.new(:tag, :total, keyword_init: true)
  # 「词表里确实没有这个词」也是结论，要能被缓存命中。
  # 用 nil 做不到——那分不清「没查过」和「查过且没有」，后者会每轮重探，
  # 而查无此词的正是最该省的那部分。
  NOT_FOUND = :not_in_tag_list

  def initialize(client:, account: nil)
    @client = client
    @account = account
    @cache = {}
  end

  # 返回 Result（tag 是真实存在的标签），词表里完全没有就返回 nil。
  #
  # 探的是**全局**有没有这个标签，不按国家探：标签存不存在是全局的事，
  # 而按国家探会把探测次数乘上市场数（12 个词 × 6 个市场 = 72 次，一轮就被限流）。
  def call(phrase)
    key = phrase.to_s.downcase.strip
    return @cache[key] if @cache.key?(key)

    # 先查落库的词表缓存：探词和挖公司走同一个 Apollo 端点，重探就是重花钱。
    # 原来只有进程内缓存，每轮任务新建一个 resolver、之前探过的全部重探——
    # 同一个 digital signage 在 11 个任务里探了 11 遍（2026-11-10 台账 406 次探词调用）。
    cached = stored_lookup(key)
    return @cache[key] = (cached == NOT_FOUND ? nil : cached) unless cached.nil?

    result = resolve(key)
    remember(key, result)
    @cache[key] = result
  end

  private

  # tag 为 nil 也是有效结论（「词表里确实没有」），同样要缓存——
  # 否则那些查无此词的反而每轮都重探，正是最该省的部分。
  def stored_lookup(key)
    return nil if @account.nil?

    row = Crm::ApolloTag.lookup(@account.id, key)
    return nil if row.nil?

    tag, total = row
    tag.nil? ? NOT_FOUND : Result.new(tag: tag, total: total)
  end

  def remember(key, result)
    return if @account.nil?
    # total 为 nil 表示这次没问到（限流/超时），不是结论，别缓存。
    return if result.is_a?(Result) && result.total.nil?

    tag = result.is_a?(Result) ? result.tag : nil
    total = result.is_a?(Result) ? result.total : nil
    Crm::ApolloTag.remember(@account.id, key, tag, total)
  end

  def resolve(phrase)
    candidates(phrase).first(MAX_PROBES).each do |cand|
      total = probe(cand)
      # nil = 这次没问到（限流/超时）。不能当成「词表里没有」——
      # 那会让一个好词被判死，然后退到更糙的词上去。直接拿原话去搜，最多搜回 0 条。
      return Result.new(tag: phrase, total: nil) if total.nil?

      next if total.zero?
      # 原话在词表里就直接用，不挑剔池子大小——那是人／画像的本意。
      return Result.new(tag: cand, total: total) if cand == phrase || total >= MIN_FALLBACK_TOTAL
    end
    category_word(phrase)
  end

  # 词组全军覆没，最后退到单个品类词。**池子最小的那个优先**——
  # 一个词里越具体的那个词池子越小：toys 六千多家 vs games 十八万家，
  # 要的是 toys。太大的（见 SINGLE_WORD_MAX）直接不要。
  def category_word(phrase)
    picks = phrase.split(/\s+/).uniq.reject { |w| w.length < 3 || GENERIC_WORDS.include?(w) }
    picks.filter_map { |word| sized(word) }
         .select { |r| r.total.between?(MIN_FALLBACK_TOTAL, SINGLE_WORD_MAX) }
         .min_by(&:total)
  end

  def sized(tag)
    total = probe(tag)
    Result.new(tag: tag, total: total) if total&.positive?
  end

  # 本机连 Apollo 会间歇性 Net::OpenTimeout / SSL eof（走代理），一次失败不代表问不到。
  # 失败重试一次就够——再失败就按「没问到」走，拿原话去搜，不瞎猜。
  def probe(tag)
    total = @client.count_companies(tag: tag)
    return total unless total.nil?

    sleep RETRY_WAIT
    @client.count_companies(tag: tag)
  end

  # 候选顺序：整句 → 从**左边**开始砍词。
  # 砍左边是因为中心词在右边：own brand consumer electronics 的落点是 consumer electronics，
  # 不是 own brand。砍到只剩一个词就停手（见 MIN_FALLBACK_WORDS）。
  def candidates(phrase)
    words = phrase.split(/\s+/).reject(&:blank?)
    return [] if words.empty?
    return [phrase] if words.size == 1

    [phrase] + (words.size - 1).downto(MIN_FALLBACK_WORDS).map { |len| words.last(len).join(' ') }
  end
end
