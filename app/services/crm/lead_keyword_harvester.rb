# 从「已经认可的公司」身上长出新关键词。
#
# 为什么需要它：翻页只能续数量，续不了质量——同一个关键词挖到第 7 页，
# 平均匹配度掉到 14.9（2026-11-08 实测，711 家新公司里只有 51 条像买家）。
# 真正要续的是**关键词**，不是页码。
#
# 料从哪来：Apollo 给每家公司打了业务标签，而且是**当地语言**的。
# 从业务员建了档的、以及模型打高分的公司身上把标签薅下来，就是下一轮的搜索词：
#   Giochi Preziosi → toy retail / children's toys / school supplies
#   Kids Licensing  → productos infantiles / licensed products（西语）
#   EXTRA Computer  → rugged tablets / industrie pcs（德语）
#
# ⚠️ 挑**具体**的，不是挑**常见**的。
# 按出现次数排的话选出来的是 b2c / e-commerce / retail / internet 这类万金油，
# 拿去搜等于没筛（第一版就是这么错的）。
class Crm::LeadKeywordHarvester
  # 万金油标签。几乎每家 B2B 公司都挂着，没有区分度。
  STOPWORDS = [
    'b2b', 'b2c', 'e-commerce', 'ecommerce', 'retail', 'wholesale', 'internet',
    'consumers', 'consumer internet', 'information technology & services',
    'manufacturing', 'technology', 'business', 'services', 'software', 'marketing',
    'sales', 'management', 'consulting', 'trading', 'import', 'export',
    'technology, information & media', 'information technology',
    # Apollo 的行业大类会混在公司标签里。它们不是品类，是整个行业——
    # 学了等于没筛（"informatica" 光意大利就 6105 家）。
    'it services & it consulting', 'information technology and services',
    'distribution', 'telecommunication', 'telecommunications', 'informatica',
    'electronics', 'hardware', 'audio', 'hospitality', 'logistics', 'automation'
  ].to_set.freeze

  # 一轮**每个市场**最多学几个新词。多了会把原来的词挤出 MAX_KEYWORDS 的配额。
  MAX_NEW = 4
  # 每个市场从几家公司身上薅。只看最认可的那几家，薅太多就稀释了。
  SOURCE_COMPANIES = 8
  # 拿来当「认可」的分数线。市场刚开张时分普遍偏低，门槛太高就一个市场都学不到。
  MIN_SOURCE_SCORE = 60
  # 一个标签至少要有这么多家认可的公司都挂着，才算品类词（见 #rank）。
  MIN_SHARED = 2
  # 标签挂着的公司超过这个数，就不是品类而是整个行业，搜它等于没筛。
  # 跟 ApolloTagResolver::SINGLE_WORD_MAX 一个道理，这里更严——
  # 学来的词是要自动用的，没人过目，宁可漏掉也别学宽。
  MAX_TAG_POOL = 20_000
  # 学来的词搜到这么多条还一点动静都没有，就算白搜，淘汰（口径见 #barren）。
  # 阈值要比默认的 8 高一些——学来的词值得多给几轮机会再判死。
  PRUNE_MIN_LEADS = 15

  def initialize(campaign:, client: nil)
    @campaign = campaign
    @account = campaign.account
    @client = client || Crm::ApolloClient.new(account: @account, scene: 'keyword_harvest')
  end

  # 返回新学到的词 [{ text:, from: 哪家公司贡献的 }]，并写进任务的关键词里。
  # 学不到就返回空数组，什么都不改。
  def call
    kept = prune
    picks = harvest
    @campaign.update!(keywords: kept + keyword_rows(picks)) if picks.any? || kept.size != Array(@campaign.keywords).size
    picks
  end

  # 自动学来的词里，搜了不少却一条都没建档的，淘汰掉。
  #
  # 不淘汰的话烂词会越积越多，把好词挤出每轮 MAX_KEYWORDS 的配额——
  # 学习机制反而越学越差。**只淘汰 kind=learned 的**，
  # 业务员和画像生成的原始词一律不动，那是人的意图，不该被统计数字否决。
  def prune
    rows = Array(@campaign.keywords)
    rows.reject { |k| k['kind'] == 'learned' && barren.include?(k['text']) }
  end

  # 判死的口径：搜了 PRUNE_MIN_LEADS 条以上，**既没建档、也一条都没过初筛**。
  #
  # 为什么要带上初筛：建档要等业务员点，比搜索慢好几周，光看建档数会把
  # 「刚搜出一批好公司、还没人看」的词和真的烂词一起淘汰掉。
  # 初筛是当轮就有的信号——过了初筛说明方向对，给它时间；
  # 一条都过不了（"environmental responsibility in tech" 这种噪音标签）才是真死。
  def barren
    stats = Crm::LeadOutcomeStats.new(campaigns: @account.crm_lead_campaigns.where(id: @campaign.id))
    stats.by_keyword
         .select { |r| r[:leads] >= PRUNE_MIN_LEADS && r[:claimed].zero? && r[:screened].zero? }
         .pluck(:keyword).to_set
  end

  private

  # 优先级：业务员建了档的 > 模型打高分的。人点出来的比模型猜的可信。
  # **按市场取**：学词的料必须来自这个市场的公司，否则学到的全是同一国的词。
  def source_leads(market)
    leads = market_leads(market)
    claimed = leads.where(status: 'CLAIMED')
    scored = leads.where(status: %w[FOUND UNLOCKED])
                  .where("(raw->>'screen_score')::int >= #{MIN_SOURCE_SCORE}")
                  .order(Arel.sql("(raw->>'screen_score')::int DESC"))
    (claimed.to_a + scored.to_a).uniq(&:domain).first(SOURCE_COMPANIES)
  end

  def market_leads(market)
    @account.crm_leads.where(crm_lead_campaign_id: @campaign.id)
            .where.not(domain: nil)
            .where("raw->>'market' = ?", market)
  end

  # **每个市场各学各的**。
  #
  # 原来是全任务挑分最高的 8 家公司，于是哪个市场的公司分高就只学到那一国的词——
  # 一个任务挂 6 个市场，实际只有一两个市场在长词。而 Apollo 的标签是**当地语言**的，
  # 本地词的通过率实测比英文词高三倍（distribuzione elettronica 71% vs
  # electronics distribution 25%，accessoires mobiles 67% vs mobile accessories 40%），
  # 所以每个市场都必须自己长。
  def harvest
    existing = existing_keywords
    Array(@campaign.target_markets).flat_map do |market|
      rank(tally(market, existing)).map { |row| row.merge(market: market) }
    end
  end

  # 这个市场的认可公司身上，每个标签被几家挂着。
  def tally(market, existing)
    seen = {}
    source_leads(market).each do |lead|
      tags_for(lead).each do |tag|
        next if existing.include?(tag)

        row = (seen[tag] ||= { text: tag, from: lead.company_name, shared: 0 })
        row[:shared] += 1
      end
    end
    seen.values
  end

  def tags_for(lead)
    org = @client.organization(domain: lead.domain)
    Array(org && org[:keywords]).filter_map { |k| clean(k) }
  end

  # 两个字以下、太长的、万金油的一律不要。
  def clean(tag)
    text = tag.to_s.strip.downcase.squeeze(' ')
    return nil if text.length < 4 || text.length > 36 || STOPWORDS.include?(text)
    return nil if text.match?(/\A[\d\s\-&,.]+\z/)

    text
  end

  def existing_keywords
    Array(@campaign.keywords).filter_map { |k| k['text'].to_s.downcase.presence }.to_set
  end

  # 挑**共现**的：几家认可的公司都挂着同一个标签，那才是品类词。
  #
  # 原来只按「词组长、字数多」排，于是从 Energy Sistem 身上学到了
  # "environmental sustainability"、"bluetooth connectivity"——Apollo 给每家公司打
  # 二三十个标签，最长的那个往往跟我们卖什么毫无关系。2026-11-08 实测：这么学来的
  # 4 个词各搜回 6 家，初筛通过 0 家。
  # 共现能自然挡掉它们：噪音标签只属于一家公司，品类词会被同行共享。
  #
  # ⚠️ **共现不够就不学，不要退而求其次。**
  # 曾经让「一家独有的标签」在凑不满 MAX_NEW 时顶上，结果刚开张的市场
  # （只有一家认可公司）学到的全是那一家的自我介绍：
  # "platform for primary school teachers"、"instant book illustration platform"。
  # 这种词会自动拿到配额去搜，学歪了比没学更糟。
  def rank(rows)
    rows.select { |r| r[:shared] >= MIN_SHARED }
        .sort_by { |r| [-r[:shared], -r[:text].count(' '), -r[:text].length] }
        .select { |r| usable_pool?(r[:text]) }
        .first(MAX_NEW)
  end

  # 太宽的标签不学。排序之后再查，省得给用不上的词白白探一次。
  def usable_pool?(tag)
    total = (@pools ||= {})[tag] ||= @client.count_companies(tag: tag)
    # nil = 这次没问到（限流/超时）。问不到就别学，下一轮还有机会。
    total.present? && total.positive? && total <= MAX_TAG_POOL
  end

  # 学到的词**只挂在它来源公司所在的市场**。
  # 以前是给每个目标市场都复制一份，于是 Juguettos（西班牙）贡献的
  # "juguetes de primera infancia" 会被拿去搜美国和德国——纯浪费配额。
  # 同一个英文标签如果在别的市场也成立，那边自然会有公司贡献它一次。
  def keyword_rows(picks)
    picks.map do |p|
      { 'market' => p[:market], 'locale' => 'auto', 'text' => p[:text],
        'kind' => 'learned', 'from' => p[:from] }
    end
  end
end
