# 自动挖完之后发给负责人的那条简报。
#
# 原来是一条机械通知：「又挖到 128 条，像买家的：·A ·B ·C」。问题是业务员看完
# 还是不知道**先打哪家、为什么**——名单他自己在页面上也能翻，这条通知没省掉任何判断。
#
# 现在把事实（背调结论、规模、门店数、效果表）摆给模型，让它写三句人话：
# 先打谁、凭什么、哪个搜索词该换掉。写不出来就退回机械版，绝不因为 AI 挂了就不通知。
class Crm::LeadDigest
  # 挑几家摆给模型。太多它会写成流水账，也把通知撑得没人看。
  MAX_PICKS = 6
  # 通知最长多少字。超了在手机上就是一屏糊脸。
  MAX_CHARS = 600

  SYSTEM = <<~PROMPT.freeze
    你在给一家中国平板工厂的外贸业务员写「今天挖到的新客户」简报。

    写法：
    - 开头一句说清楚今天挖到多少、值得先看的有几家。
    - 然后**最多 3 家**，每家一行：公司名 + 一句为什么值得先打（用给你的背调和规模说话，
      不要写「可能是潜在客户」这种空话）。
    - 如果给了「白搜的搜索词」，最后加一行点名，建议换掉。
    - 全文不超过 200 字，不要标题、不要客套、不要 emoji。
    - **只用给你的事实**，不要编造公司背景、不要猜客户需求。

    只返回一个 JSON 对象，不要代码块包裹：{"brief": "简报正文"}
  PROMPT

  def initialize(campaign:, created:, learned: [])
    @campaign = campaign
    @account = campaign.account
    @created = created
    @learned = learned
  end

  # 返回通知正文。AI 不可用/写砸了都回退到机械版。
  def call
    picks = top_leads
    return nil if picks.empty?

    ai_text(picks).presence || plain_text(picks)
  end

  private

  def ai_text(picks)
    parsed = Crm::EmailAiService.new(account: @account, purpose: 'lead_digest')
                                .ask_json(SYSTEM, facts(picks))
    text = parsed.is_a?(Hash) ? parsed['brief'].to_s : nil
    return nil if text.blank?

    clip([prefix + text.strip, learned_line].compact.join("\n"))
  rescue StandardError => e
    Rails.logger.info("[LeadDigest] campaign=#{@campaign.id} 写简报失败，退回机械版: #{e.class} #{e.message}")
    nil
  end

  def facts(picks)
    [
      "任务：#{@campaign.name}；这一轮新挖到 #{@created} 条线索。",
      "值得先看的几家：\n#{picks.map { |l| "- #{lead_facts(l)}" }.join("\n")}",
      barren_line
    ].compact.join("\n\n")
  end

  def lead_facts(lead)
    raw = lead.raw
    ([lead.company_name, lead.country, lead.industry, "匹配度 #{raw['screen_score']}",
      why_text(raw)] + size_bits(raw['org'] || {})).compact_blank.join('｜')
  end

  # 背调读过官网，比初筛看名字猜的硬气，有就用它那句。
  def why_text(raw)
    note = raw.dig('bg', 'note')
    note.present? ? "背调：#{note}" : raw['screen_why']
  end

  # 门店数和营收是「吃不吃得下 3000 台一单」最直接的依据。
  def size_bits(org)
    [org['retail'].to_i.positive? ? "#{org['retail']} 家门店" : nil,
     org['revenue'].presence && "营收 #{org['revenue']}"]
  end

  # 白搜的词：这张表唯一能改的动作就是换掉它们，所以单独喂给模型。
  def barren_line
    words = Crm::LeadOutcomeStats.new(campaigns: @account.crm_lead_campaigns.where(id: @campaign.id))
                                 .barren_keywords.pluck(:keyword)
    return nil if words.empty?

    "白搜的搜索词（搜了不少一个都没建档）：#{words.join('、')}"
  end

  # 学到的新词是死数据，**不喂给模型**：它分不清「学到的新词」和「白搜该换的词」，
  # 2026-11-08 实测把刚学到的 kassensysteme 写成了「建议换掉」。机械地附在后面就行。
  def learned_line
    return nil if @learned.blank?

    "（这一轮从你认可的公司身上学到新搜索词：#{@learned.pluck(:text).join('、')}）"
  end

  # 背调过的排前面——有背调的那几家才讲得出「凭什么先打」。
  def top_leads
    @campaign.leads.where(status: 'FOUND').where("raw->>'screen' = 'yes'")
             .where('crm_leads.created_at > ?', 1.hour.ago)
             .order(Arel.sql("(raw ? 'bg') DESC, (raw->>'screen_score')::int DESC"))
             .limit(40).to_a.uniq(&:company_name).first(MAX_PICKS)
  end

  def prefix = "【新客开发】「#{@campaign.name}」\n"

  def plain_text(picks)
    lines = picks.first(5).map { |l| "· #{l.company_name}#{"（#{l.industry}）" if l.industry.present?}" }
    body = "#{prefix}又挖到 #{@created} 条线索，其中像买家的：\n#{lines.join("\n")}"
    clip([body, learned_line].compact.join("\n"))
  end

  def clip(text) = text.length > MAX_CHARS ? "#{text[0, MAX_CHARS]}…" : text
end
