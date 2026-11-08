# 生成「理想客户画像 + 本地化搜索关键词」，给主动拓客用。
#
# 和同类产品最大的不同在**喂给模型的料**：它们只能抓你的官网（抓失败就是一片
# 「资料未提供」），而我们手上是十三年的真实生意——13306 个客户档案、610 张订单、
# 205 张 PI。官网说的是「我们想卖什么」，订单说的是「客户真的买了什么」，后者准得多。
#
# ⚠️ 画像里**哪几条有真实数据撑着、哪几条是模型推的，必须分开标**（evidence）。
# 拿一个凭空推断出来的「目标行业」去发开发信，错的不只是一封信。
class Crm::LeadProfileBuilder
  # 统计口径：只看真成交过的客户，没成交的参考价值有限。
  TOP_COUNTRIES = 8
  TOP_PRODUCTS = 10
  # 一个市场出几个关键词。再多就是同义词堆砌，搜出来的公司高度重合。
  KEYWORDS_PER_MARKET = 10

  SYSTEM = <<~PROMPT.freeze
    你在给一家中国外贸制造企业做「主动找客户」的前期分析。下面给你的是这家公司
    **真实的成交数据**（不是宣传材料）。

    任务：出两样东西。
    ① 理想客户画像：决策人角色、目标行业、公司规模、地理重点。
    ② 每个目标市场的本地化搜索关键词，用于在企业数据库里检索潜在买家。

    规矩：
    - 画像的每一条都要标 `evidence`：有成交数据直接支撑的写 "data"，你自己推断的写 "inferred"。
      **宁可标 inferred，也不要假装有依据**——这些条目后面是要拿去发开发信的。
    - 关键词必须用该市场的**当地商业用语**（德国用德语、法国用法语、美国用英语），
      不要把中文词直译过去。每个关键词标一个 kind：
      wholesale（分销商/批发）、buyer_role（采购角色）、niche（细分场景）、category（品类词）。
    - 关键词要能在企业库里搜到**买家**，不是搜到同行。
    - 关键词必须是企业库里真实存在的**行业标签**，所以：**一到两个词**，用行业里的叫法
      （spielwaren / juguetes / consumer electronics / rugged tablets / electronics distribution）。
      别写三四个词的描述性短语——"own brand consumer electronics"、"kids tablet" 这种
      企业库里根本没有这个标签，一条都搜不到。
    - 不要写「应该更精准地定位」这类没有可执行动作的话。
    - 如果给了「历史战绩」,**已经带来过客户的词要保留或做同类扩展**,
      白搜的词别再出同义词——那个方向已经试过了。

    只返回一个 JSON 对象，不要代码块包裹：
    {
      "persona": {
        "decision_roles": {"value": "...", "evidence": "data|inferred"},
        "industries":     {"value": "...", "evidence": "data|inferred"},
        "company_size":   {"value": "...", "evidence": "data|inferred"},
        "geography":      {"value": "...", "evidence": "data|inferred"}
      },
      "keywords": [
        {"market": "GERMANY", "locale": "de_DE", "text": "...", "kind": "wholesale"}
      ]
    }
  PROMPT

  def initialize(campaign:)
    @campaign = campaign
    @account = campaign.account
  end

  # 返回 true 表示画像已经写进 campaign。失败不抛异常——任务停在 DRAFT，人能重跑。
  def call
    facts = collect_facts
    parsed = Crm::EmailAiService.new(account: @account, purpose: 'lead_profile')
                                .ask_json(SYSTEM, prompt_for(facts))
    return false unless parsed.is_a?(Hash) && parsed['persona'].present?

    @campaign.update!(
      profile: parsed['persona'], keywords: Array(parsed['keywords']),
      evidence: { facts: facts, inferred: inferred_fields(parsed['persona']) },
      run_model: Crm::AiSetting.for_account(@account).model,
      status: 'PROFILED', profiled_at: Time.current, last_error: nil
    )
    true
  rescue StandardError => e
    @campaign.update(status: 'DRAFT', last_error: "#{e.class}: #{e.message}".truncate(300))
    false
  end

  private

  # 喂给模型的全是**可核对的事实**，不是形容词。
  def collect_facts
    {
      top_countries: top_countries,
      top_products: top_products,
      deal_customer_count: won_customers.count,
      target_markets: @campaign.target_markets,
      product_hint: @campaign.product_hint.presence,
      seed_keywords: @campaign.seed_keywords.presence,
      proven_keywords: outcome_stats.proven_keywords.presence,
      barren_keywords: outcome_stats.barren_keywords.presence
    }.compact
  end

  # 历史战绩:以前搜过的词哪些真带来了客户、哪些白搜。
  # 这是这套东西和纯搜索工具的分水岭——它每次都从零开始猜,我们每多跑一轮就多一点依据。
  # 口径是**全账号累计**(不是本任务),经验该是全公司共享的。
  def outcome_stats
    @outcome_stats ||= Crm::LeadOutcomeStats.new(campaigns: @account.crm_lead_campaigns)
  end

  def won_customers
    @won_customers ||= @account.crm_customers.where('deal_order_count > 0')
  end

  # 按成交额排的国家：这就是「我们的货实际卖到哪儿」，比任何市场调研都准。
  def top_countries
    won_customers.where.not(trade_country: nil)
                 .group(:trade_country)
                 .sum(Arel.sql('COALESCE(deal_total_amount_micros, 0)'))
                 .sort_by { |_, v| -v }.first(TOP_COUNTRIES)
                 .map { |country, micros| { country: country, deal_rmb: (micros / 1_000_000.0).round } }
  end

  # 真卖出去的产品和均价（从订单明细里数，不是产品档案里躺着的那些）。
  # 均价很关键：它决定了该找哪一档买家——卖 $49 的平板和卖 $800 的大屏，客户完全是两拨人。
  def top_products
    rows = @account.crm_sales_orders.where.not(status: 'CANCELLED')
                   .pluck(:line_items).flatten.select { |i| i.is_a?(Hash) }
    rows.filter_map { |i| product_row(i) }
        .group_by { |r| r[:name].downcase }
        .map { |_, group| merge_product(group) }
        .sort_by { |r| -r[:times] }.first(TOP_PRODUCTS)
  end

  def product_row(item)
    name = item['name'].to_s.strip
    price = item['unit_price'].to_f
    return nil if name.blank? || name.length > 40

    { name: name, price: price }
  end

  def merge_product(group)
    prices = group.filter_map { |r| r[:price] if r[:price].to_f.positive? }
    { name: group.first[:name], times: group.size,
      avg_price: prices.any? ? (prices.sum / prices.size).round(2) : nil }.compact
  end

  def prompt_for(facts)
    <<~TEXT
      公司真实成交数据：
      · 成交过的客户数：#{facts[:deal_customer_count]}
      · 货实际卖到哪些国家（按成交额，单位人民币）：
      #{facts[:top_countries].map { |c| "    #{c[:country]}：#{c[:deal_rmb]}" }.join("\n")}
      · 真实卖出去的产品（出现次数 / 平均单价 USD）：
      #{facts[:top_products].map { |p| "    #{p[:name]}：#{p[:times]} 次#{p[:avg_price] ? " / $#{p[:avg_price]}" : ''}" }.join("\n")}

      这次要开拓的目标市场：#{Array(facts[:target_markets]).join('、')}
      #{facts[:product_hint] ? "本次主推产品：#{facts[:product_hint]}" : ''}
      #{facts[:seed_keywords] ? "业务员给的种子关键词：#{facts[:seed_keywords]}" : ''}

      #{history_section(facts)}
      每个目标市场给 #{KEYWORDS_PER_MARKET} 个关键词。
    TEXT
  end

  # 没跑过搜索时这段是空的(第一轮本来就没战绩),别给模型一堆空标题。
  def history_section(facts)
    proven = facts[:proven_keywords]
    barren = facts[:barren_keywords]
    return '' if proven.blank? && barren.blank?

    [
      '以前搜过的关键词战绩:',
      proven.present? ? "· 带来过客户的词(建档数 / 成交额人民币):\n#{keyword_lines(proven)}" : nil,
      barren.present? ? "· 搜出一堆但一个都没建档的词(线索数):\n#{keyword_lines(barren, counts: false)}" : nil
    ].compact.join("\n")
  end

  def keyword_lines(rows, counts: true)
    rows.map do |r|
      counts ? "    #{r[:keyword]}：#{r[:claimed]} 家 / #{r[:deal_rmb]}" : "    #{r[:keyword]}：#{r[:leads]} 条"
    end.join("\n")
  end

  # 把标成 inferred 的字段单独拎出来，前端据此显示「这几条是推的，发信前先核实」。
  def inferred_fields(persona)
    persona.select { |_, v| v.is_a?(Hash) && v['evidence'] == 'inferred' }.keys
  end
end
