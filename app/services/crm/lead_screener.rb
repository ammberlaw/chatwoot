# 搜回来的线索再过一道：这家公司到底像不像我们的买家。
#
# 为什么必须有这一步：Apollo 的关键词是**模糊匹配**，搜「Digital Signage Distributor」
# 会把德国商报、经济周刊、t3n 科技媒体、招聘公司全带出来——它们只是报道过
# 或招聘过相关岗位（2026-11-06 实测 111 条线索里一大半是这种）。
# 搜出来的是「提到过这个词的公司」，不是「买这个东西的公司」。
#
# 行业字段指望不上（Apollo 那个搜索接口不返回 industry，实测 111 条全空），
# 所以靠 AI 看公司名和域名判断。这恰恰是纯搜索工具做不了、而我们有的东西。
#
# **不自动删**：AI 也会看走眼，只打标，让业务员自己定。
#
# ⚠️ 这一步要在**抓联系人之前**跑（见 Crm::LeadSearchRunner）。
# 判断用的东西——公司名、域名、行业代码、营收、门店数——搜索阶段全都有了，
# 一个都不来自联系人。2026-11-07 实测：73 家公司里 53 家（73%）被判「不是买家」，
# 而我们当时给这 53 家挨个搜了联系人，等于七成的 Apollo 调用白花。
class Crm::LeadScreener
  # 一批送多少家公司给模型。太多会让它敷衍，太少则调用次数上去了。
  BATCH = 30
  VERDICTS = %w[yes no unsure].freeze
  # 品牌授权渠道压到的分数。不给 0——留一点余地，万一人想翻出来看。
  BRAND_CHANNEL_SCORE = 5

  SYSTEM = <<~PROMPT.freeze
    你在帮一家中国工厂筛选「主动开发」搜回来的潜在客户名单。这家工厂做的是
    商用显示设备（平板电脑、触摸一体机、工业显示器、数字标牌），单价几十到几百美金，
    买家通常是**分销商、系统集成商、设备供应商、连锁零售/教育/餐饮的采购方**。

    下面是一批公司，每行给的是：公司名（域名）· 行业 · 营收 · 门店数。
    行业是 NAICS 官方行业代码翻过来的，**不是猜的，可信度高于公司名**。
    判断每一家**有没有可能是这类买家**。

    判断要点：
    - 媒体、杂志、新闻网站、招聘公司、猎头、咨询公司、行业协会 → 一律 no。
      它们只是报道过或招聘过相关岗位，才被关键词搜出来的。
    - 如果给了**背调**（以「背调：」开头的那段），它是 AI 真去读了官网得出的，
      **可信度高于公司名和行业代码**，按它判：
      · 背调说这家是同行、竞争对手、做一样产品的厂商 → no（他们不会找我们代工）
      · 背调说这家是某品牌的授权经销商/独家总代/品牌专卖 → no（卖的是品牌方的货）
      · 背调说这家是行业协会、倡议组织、媒体、咨询 → no
      · 背调说它采购/分销/零售我们这类产品 → yes，分数可以给高
      背调和公司名打架时，以背调为准。
    - **品牌授权渠道 → no**：OPPO 意大利独家总代、三星品牌专卖、小米授权经销商这一类。
      它们卖的是品牌方的货，包装系统货源全由品牌方定，不会回头找工厂做自己的牌子。
      ⚠️ 别被「经销商/分销商」几个字带偏——判据是「名字里带某个手机/消费电子品牌
      + 授权/独家/专卖字样」。同时代理多个品牌、没有授权字样的分销商不算，那是正常买家。
    - 银行、保险、律所、医院、政府机关 → no（除非名字明确显示是设备采购实体）。
    - 分销商、批发商、系统集成商、AV/IT 设备商、标识标牌公司、连锁零售/餐饮/教育 → yes。
    - 看不出是做什么的 → unsure，不要硬猜。
    - 行业写着「期刊出版 / 报纸出版 / 广播电视 / 影视制作 / 职业介绍 / 劳务派遣 /
      管理咨询 / 广告代理 / 行业协会 / 政府机构 / 银行 / 保险 / 律所」→ 直接 no。
      这些就是被关键词模糊匹配带进来的。
    - 行业写着「电子元器件批发 / 计算机设备批发 / 商用设备批发 / 音视频设备制造 /
      计算机外设制造 / 系统集成 / 零售 / 酒店住宿 / 餐饮 / 学校」→ 倾向 yes。
    - ⚠️「批发分销」「制造」「专业服务」这几个是笼统大类，**不算正信号**——
      卫浴批发、光伏批发、食品批发、机器人制造都落在这里。看公司名定，别因为是批发就往 yes 拉。
    - 有门店数的是连锁终端，门店越多越值得跟。
    - unsure 只留给**真看不出这家做什么**的。如果你的理由写得出「做 XX 的，不是买我们这类」，
      那就是 no，别给 unsure——给了 unsure 等于把活原样推回给业务员。

    如果给了「业务员以前的判断」，那是**人看过之后的结论，比上面的通则优先**。
    特别是「AI 说像、人却不要」那几条，照着它们的共性往严判。

    除了结论，再给一个 **0–100 的匹配度分**（score）：
    100 = 完全就是我们要找的那类；70 以上 = 值得业务员花时间；
    40 左右 = 沾边但不确定；10 以下 = 明显不是。
    打分要能把同样判 yes 的几家**分出先后**，别一律给 90。

    只返回一个 JSON 对象，不要代码块包裹，results 里的顺序和输入一致：
    {"results": [{"i": 0, "verdict": "yes|no|unsure", "score": 0, "why": "不超过12个字的理由"}]}
  PROMPT

  # 给一批公司出判定，和线索表无关——搜索途中就能调。
  # items: [{ name:, domain:, industry:, revenue:, retail:, listed: }]
  # 返回 { 公司名 => { verdict:, why: } }。失败返回空 Hash，调用方按「没判过」处理。
  # product_hint：这次任务主推什么。**必须带上**——同一家工厂，卖教育平板和卖数字标牌
  # 的买家完全是两拨人（前者是教育科技分销和儿童电子品类，后者是 AV 集成和标识工程）。
  # 不带的话模型只会按 SYSTEM 里那套通用标准判，任务越细分越不准。
  def self.verdicts_for(account:, items:, product_hint: nil, criteria: nil)
    items = items.reject { |i| i[:name].blank? }.uniq { |i| i[:name] }
    return {} if items.empty?

    memo = Crm::LeadScreenMemory.new(account: account).prompt_block
    focus = focus_block(product_hint: product_hint, criteria: criteria)
    items.each_slice(BATCH).reduce({}) do |acc, batch|
      acc.merge(judge_batch(account, memo, batch, focus))
    end
  end

  def self.judge_batch(account, memo, batch, focus = nil)
    listing = batch.each_with_index.map { |item, i| "#{i}. #{describe_item(item)}" }
    content = [focus, memo, "待判断的公司：\n#{listing.join("\n")}"].compact.join("\n\n")
    rows = extract_rows(Crm::EmailAiService.new(account: account, purpose: 'lead_screen')
                          .ask_json(SYSTEM, content))
    collect_verdicts(rows, batch)
  rescue StandardError => e
    Rails.logger.warn("[LeadScreener] 公司级初筛失败: #{e.class} #{e.message}")
    {}
  end
  private_class_method :judge_batch

  def self.collect_verdicts(rows, batch)
    rows.each_with_object({}) do |row, acc|
      item = batch[row['i'].to_i]
      next if item.nil?

      acc[item[:name]] = brand_channel_verdict(item) || model_verdict(row)
    end
  end
  private_class_method :collect_verdicts

  # 品牌授权渠道一律按规则压掉，不看模型怎么说。
  # 2026-11-08 实测：「Otech - OPPO Authorized Exclusive Distributor Italia」营收 1.4 亿、
  # 有零售渠道、正好做平板，模型给了 85 分——各项信号确实都像，但它永远不会定制我们的牌子。
  def self.brand_channel_verdict(item)
    return nil unless Crm::BrandChannel.brand_channel?(name: item[:name], domain: item[:domain])

    { verdict: 'no', score: BRAND_CHANNEL_SCORE, why: '品牌授权渠道，不做自有品牌' }
  end
  private_class_method :brand_channel_verdict

  def self.model_verdict(row)
    verdict = VERDICTS.include?(row['verdict']) ? row['verdict'] : 'unsure'
    { verdict: verdict, score: clamp_score(row['score']), why: row['why'].to_s.truncate(30) }
  end
  private_class_method :model_verdict

  # 分数兜底：模型偶尔不给或给个离谱值。没给就按结论折算一个保守值，
  # 否则排序会把「没打分」的全冲到最后面。
  def self.clamp_score(raw)
    raw.to_s[/\d+/]&.to_i&.clamp(0, 100)
  end
  private_class_method :clamp_score

  # 主推产品 + 业务员补的条件，拼成送给模型的那段。两个入口共用。
  # 业务员补的条件优先级**高于**通则——通用标准不可能覆盖所有场景，
  # 「只要有自己门店的」「排掉纯线上代运营的」这种只有跑业务的人知道。
  def self.focus_block(product_hint: nil, criteria: nil)
    [
      product_hint.presence && "这次要开发的是：#{product_hint}。**按这个产品的买家来判**，不是按通用品类。",
      criteria.presence && "业务员给这次任务补的条件（**优先级高于上面的通则**）：\n#{criteria}"
    ].compact.join("\n").presence
  end

  # 送给模型的一行。两个入口（公司级 / 线索级）共用，免得两边说法不一致。
  def self.describe_item(item)
    bits = ["#{item[:name]}#{item[:domain].present? ? " (#{item[:domain]})" : ''}"]
    bits << "行业 #{item[:industry]}" if item[:industry].present?
    bits << "营收 #{item[:revenue]}" if item[:revenue].present?
    bits << "门店 #{item[:retail]} 家" if item[:retail].to_i.positive?
    bits << '上市公司' if item[:listed].present?
    # 背调放最后、单独起头：它是三方信息里唯一真读过官网的，提示词里让模型按它优先判。
    bits << "背调：#{item[:bg]}" if item[:bg].present?
    bits.join(' · ')
  end

  def initialize(campaign:)
    @campaign = campaign
    @account = campaign.account
  end

  # 返回判定过的公司数。失败只记日志——筛选失败不该让整批线索作废。
  def call
    companies = pending_companies
    return 0 if companies.empty?

    companies.each_slice(BATCH).sum { |batch| screen_batch(batch) }
  end

  # 三种形态都接住：直接数组、{"results": [...]}、
  # 以及 ask_json 把裸数组塞进 {"note": "<JSON 字符串>"} 的那种（实测会发生）。
  def self.extract_rows(parsed)
    return parsed if parsed.is_a?(Array)
    return [] unless parsed.is_a?(Hash)
    return Array(parsed['results']) if parsed['results'].present?

    parse_note(parsed['note'])
  end
  private_class_method :extract_rows

  private

  # 按公司去重（一家公司可能对应好几个联系人，判一次就够）。
  # 带上搜索阶段白给的行业/营收/门店数——这些是硬事实，比让模型看着公司名猜准得多。
  def pending_companies
    @campaign.leads.where(status: %w[FOUND UNLOCKED])
             .where("COALESCE(raw->>'screen', '') = ''")
             .select(:company_name, :domain, :industry, :raw)
             .uniq(&:company_name).reject { |lead| lead.company_name.blank? }
  end

  def screen_batch(batch)
    listing = batch.each_with_index.map { |lead, i| "#{i}. #{describe(lead)}" }
    content = [campaign_focus, learned_block, "待判断的公司：\n#{listing.join("\n")}"].compact.join("\n\n")
    parsed = Crm::EmailAiService.new(account: @account).ask_json(SYSTEM, content)
    rows = self.class.extract_rows(parsed)
    return 0 if rows.empty?

    rows.sum { |row| stamp(batch, row) }
  rescue StandardError => e
    Rails.logger.warn("[LeadScreener] campaign=#{@campaign.id}: #{e.class} #{e.message}")
    0
  end

  # 任务自己的那段：主推产品 + 业务员补的条件。和公司级初筛共用同一套说法。
  def campaign_focus
    @campaign_focus ||= self.class.focus_block(product_hint: @campaign.product_hint,
                                               criteria: @campaign.screen_criteria)
  end

  # 判例库见 Crm::LeadScreenMemory（同一份判例在获客效果面板里也露出来，
  # 省得点错了之后没人知道模型被教成了什么样）。
  def learned_block
    @learned_block ||= Crm::LeadScreenMemory.new(account: @account).prompt_block
  end

  def self.parse_note(note)
    return [] if note.blank?

    parsed = JSON.parse(note.to_s)
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end
  private_class_method :parse_note

  def describe(lead)
    org = lead.raw['org'] || {}
    self.class.describe_item(name: lead.company_name, domain: lead.domain, industry: lead.industry,
                             revenue: org['revenue'], retail: org['retail'], listed: org['listed'])
  end

  # 判定写回这家公司名下的所有线索（同一家公司的几个联系人共享结论）。
  def stamp(batch, row)
    name = batch[row['i'].to_i]&.company_name
    return 0 if name.blank?

    verdict = VERDICTS.include?(row['verdict']) ? row['verdict'] : 'unsure'
    patch = { 'screen' => verdict, 'screen_why' => row['why'].to_s.truncate(30),
              'screen_score' => self.class.send(:clamp_score, row['score']) }.compact
    @campaign.leads.where(company_name: name).find_each do |lead|
      lead.update_columns(raw: lead.raw.merge(patch)) # rubocop:disable Rails/SkipsModelValidations
    end
    1
  end
end
