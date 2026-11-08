# 把公司从 Apollo 捞上来：按市场分配额、按关键词翻页、跨轮次去重。
#
# 从 Crm::LeadSearchRunner 拆出来——那边管「捞上来之后怎么处理」（抓联系人、建线索、
# 初筛、排背调），这边只管「怎么把新公司捞上来」。两件事的坑完全不同。
#
# 这个类存在的理由就一句话：**让重复跑能挖到新东西**。
# 2026-11-08 之前 Apollo 的 page 写死 1，一个关键词永远只有前 25 条，
# 任务4 的 232 家公司 100% 又出现在任务5 里——那台机器是不可持续的。
class Crm::LeadCompanyCollector
  # 每次任务的硬上限。不是为了省钱（用户说钱不是问题），是防程序出 bug 时失控，
  # 以及一次塞几千条进来没人看得过来。
  MAX_KEYWORDS = 12
  COMPANIES_PER_KEYWORD = 25
  # 公司上限。初筛移到抓联系人之前以后，贵的那一步（挨家搜联系人）只落在通过初筛的
  # 公司上，于是同样的时间能多搜一倍公司。2026-11-07 实测基线：80 家公司里只有 13 家
  # 像买家，却为 73 家都搜了联系人、耗时 146 秒。
  MAX_COMPANIES = 160
  # 单个市场的保底额度：市场多的时候均分下来不能少到没意义。
  MIN_PER_MARKET = 40
  # 单个关键词的保底额度。词多的时候均分下来每个只剩两三家就没意义了，
  # 但也不能太大——太大第一个词又会把别人的份吃掉。
  MIN_PER_KEYWORD = 6
  # 没搜过的词的权重（同 LeadOutcomeStats 的先验 1/5）。
  DEFAULT_WEIGHT = 0.2
  # 一个关键词一轮最多往下翻几页。翻太深相关性就掉了，留给下一轮。
  MAX_PAGES_PER_RUN = 3
  # 公司规模。排掉 1000 人以上的巨头和 10 人以下的小作坊——
  # 我们卖的是 $107 的儿童平板、$271 的商用一体机，买家是中小型分销商和系统集成商
  # （画像自己算出来的也是「10-200 人」）。
  # 不设这个，第一次实测搜出来的是西门子、拜耳、德意志银行、SAP，一条能用的都没有。
  EMPLOYEE_RANGES = ['11,20', '21,50', '51,100', '101,200', '201,500', '501,1000'].freeze

  # Apollo 的 organization_locations 要英文国家名，不是我们的枚举值。
  # ⚠️ 缩写要特判：直接 capitalize 会把 USA 变成「Usa」。
  ACRONYMS = { 'USA' => 'USA', 'UK' => 'UK', 'UAE' => 'UAE' }.freeze

  def initialize(campaign:, client:)
    @campaign = campaign
    @account = campaign.account
    @client = client
    @resolver = Crm::ApolloTagResolver.new(client: client)
    # 词表里查不到的搜索词，记下来给调用方（跑完要让人看见哪些词是白写的）。
    @dead_keywords = []
  end

  attr_reader :dead_keywords

  def call
    markets = Array(@campaign.target_markets)
    return [] if markets.empty?

    quota = [MAX_COMPANIES / markets.size, MIN_PER_MARKET].max
    @cursor = @campaign.search_cursor.dup
    @known = known_companies
    seen = {}
    markets.each { |market| collect_market(market, quota, seen) }
    @campaign.update_columns(search_cursor: @cursor) # rubocop:disable Rails/SkipsModelValidations
    seen.values
  end

  # **全公司**已经搜到过的公司，不只是本任务。
  #
  # ⚠️ 2026-11-08 之前只看本任务，于是两个任务配了同样的关键词就捞回同一批公司——
  # 实测任务 9 和 10（词完全相同、前后脚跑）**153 家里重合 152 家，99%**。
  # 十个业务员同时用，第一天就会全员撞在同一批 150 家公司上，而且因为线索按
  # 任务负责人隔离，谁也看不见自己在和同事抢同一家。
  #
  # 全公司已经搜到过的公司——**不分任务、不分归属**。
  #
  # 线索是共享池：一家公司进池一次就够了，谁领谁得（见 Crm::Lead 的 owner_id）。
  # 再挖一遍只会在池子里多出一行同样的公司。
  #
  # ⚠️ 2026-11-08 之前只看本任务，于是两个任务配了同样的关键词就捞回同一批公司——
  # 实测任务 9 和 10（词完全相同、前后脚跑）**153 家里重合 152 家，99%**。
  def known_companies
    @account.crm_leads.pluck(:domain, :company_name).flat_map { |d, n| [d, n] }.compact.to_set
  end

  # 一个市场搜到配额就停，不挤占别人的。
  # 每个关键词从**上次挖到的下一页**开始，挖完把游标存回去——这样每次重跑都是新的一层。
  #
  # ⚠️ 配额要**再往下分到每个关键词**，不能让第一个词吃光。
  # 2026-11-08 之前只按市场分：第一个关键词翻 3 页最多 75 家，一下超过市场配额 40，
  # 后面 11 个词永远轮不到——一个配了 12 个词的任务，780 条线索全来自
  # `kids tablet` 一个词。用户反馈的「不精准」，一半根子在这儿。
  #
  # 而且**不是平均分**：按这个词过往的初筛通过率加权（见 LeadOutcomeStats#screen_weights）。
  # 同一个任务里各词差到 35% vs 0%，平均分等于把一半额度浇在已知不长东西的地里。
  def collect_market(market, quota, seen)
    words = @campaign.keywords_for(market)
    return if words.empty?

    taken = 0
    plan_for(words, quota).each do |keyword, want|
      break if taken >= quota

      taken += harvest_keyword(market, keyword, seen, [want, quota - taken].min)
    end
  end

  # 排出「这一轮谁上场、各分几家」。
  #
  # 关键是**不是所有词都上场**：一个市场只有 40 家的额度，12 个词平摊下来每个三家，
  # 翻一页都不够，等于 12 个词都没搜。所以按权重排队，这一轮只上 quota / MIN_PER_KEYWORD
  # 个词，每个词至少 MIN_PER_KEYWORD 家。通过率低的词自然排到后面，下轮再说——
  # 新词的先验（DEFAULT_WEIGHT）比验证过很差的词高，所以新词不会被老差词挡在门外。
  # ⚠️ **先排序再截断，顺序不能反。**
  # 2026-11-08 踩过：先 first(MAX_KEYWORDS) 再按权重排，而学来的新词是追加在
  # 关键词数组末尾的——一个市场攒到 20 个词之后，学到的词永远被截在门外，
  # 学习回路看着接上了，实际一次都没用上。
  def plan_for(words, quota)
    weights = screen_weights
    # 废词直接不上场（评级见 Crm::KeywordGrade）：搜够了一个都不过初筛的词，
    # 留着只会把额度从好词那里分走。词还在列表里，人想救可以手动改。
    live = words.reject { |k| k['grade'] == 'dead' }
    live = words if live.empty?
    ranked = live.sort_by { |k| -weights.fetch(k['text'], DEFAULT_WEIGHT) }
                 .first(MAX_KEYWORDS)
                 .first([quota / MIN_PER_KEYWORD, 1].max)
    total = ranked.sum { |k| weights.fetch(k['text'], DEFAULT_WEIGHT) }
    ranked.map do |keyword|
      weight = weights.fetch(keyword['text'], DEFAULT_WEIGHT)
      [keyword, [(quota * weight / total).round, MIN_PER_KEYWORD].max]
    end
  end

  # 每个搜索词过往的初筛通过率，按词缓存一轮。
  def screen_weights
    @screen_weights ||= Crm::LeadOutcomeStats.new(
      campaigns: @account.crm_lead_campaigns.where(id: @campaign.id)
    ).screen_weights
  end

  # 先把搜索词翻成 Apollo 真实存在的标签（见 Crm::ApolloTagResolver）。
  # 翻不出来的直接跳过——以前这种词会被按空格拆开硬搜，捞回来全是广告代理和猎头。
  def harvest_keyword(market, keyword, seen, want)
    country = country_name(market)
    tag = @resolver.call(keyword['text'])
    if tag.nil?
      @dead_keywords << { market: market, text: keyword['text'] }
      return 0
    end

    # matched_keyword 存人写的词（统计口径不变），apollo_tag 存真正搜的标签。
    meta = { market: market, matched_keyword: keyword['text'], apollo_tag: tag.tag }
    harvest_tag(tag.tag, country, meta, seen, want)
  end

  # 一个标签往下翻几页，直到凑够该出的量或者翻到底。
  # 游标按标签存——换了标签就是新的一摊，页码不能接着上一个词数。
  #
  # ⚠️ 起始页取**全公司最深的那一页**，不是本任务的。
  # 光做去重不够：别人已经把前三页挖干净了，我还从第 1 页开始翻，
  # 翻回来的全是「已知」，配额空转、一条新的都挖不到。
  def harvest_tag(tag, country, meta, seen, want)
    slot = "#{meta[:market]}|#{tag}"
    page = [@cursor[slot].to_i, account_cursor[slot].to_i].max + 1
    got = 0
    deadline = page + MAX_PAGES_PER_RUN - 1
    while got < want && page <= deadline
      rows = @client.search_companies(country: country, keywords: tag,
                                      limit: COMPANIES_PER_KEYWORD, page: page,
                                      employee_ranges: EMPLOYEE_RANGES)
      break if rows.empty?

      got += take_rows(rows, seen, meta, want - got)
      @cursor[slot] = page
      page += 1
    end
    got
  end

  # 全公司各任务挖到的最深页码 { "市场|标签" => 页 }。
  # 一次算好缓存住：任务数不多，但每个关键词都要查一次。
  def account_cursor
    @account_cursor ||= @account.crm_lead_campaigns.pluck(:search_cursor).compact
                                .each_with_object({}) do |cursor, acc|
      cursor.each { |slot, page| acc[slot] = [acc[slot].to_i, page.to_i].max }
    end
  end

  def take_rows(rows, seen, meta, want)
    taken = 0
    rows.each do |company|
      break if taken >= want

      key = company[:domain].presence || company[:name]
      # 跨轮次去重：这家已经在本任务里了就跳过，别占配额。
      next if seen.key?(key) || @known.include?(key)

      seen[key] = company.merge(meta)
      taken += 1
    end
    taken
  end

  def country_name(market)
    key = market.to_s.upcase
    ACRONYMS[key] || key.split('_').map(&:capitalize).join(' ')
  end
end
