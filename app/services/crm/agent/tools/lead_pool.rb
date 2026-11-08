# 新客开发的线索池：按市场、分数、状态捞一批出来。
#
# 为什么要有：线索现在只能在「新客开发」板块一页页翻。业务员问
# 「意大利那批 70 分以上的还有哪些没处理」，agent 以前只能让他自己去翻。
#
# 每行开头给 ID——建档、丢弃、排背调都要拿这个 ID 动手，不给就得再查一遍。
class Crm::Agent::Tools::LeadPool < Crm::Agent::Tools::Base
  description '查新客开发搜回来的潜在客户线索。可按市场、最低匹配度、状态筛。按提问人自己的数据权限范围查。'
  param :market, desc: '市场：USA / UK / GERMANY / FRANCE / ITALY / SPAIN，不传=全部', required: false
  param :min_score, type: 'integer', desc: '最低匹配度 0-100，默认 70', required: false
  param :status, desc: 'open 未处理（默认）｜claimed 已建档｜discarded 已丢弃｜all 全部', required: false
  param :campaign, desc: '任务名关键词，例如「商务平板」；不传=全部任务', required: false
  param :limit, type: 'integer', desc: '最多列几条，默认 15，上限 40', required: false

  DEFAULT_SCORE = 70
  MAX_LIMIT = 40
  STATUS_SETS = { 'open' => %w[FOUND UNLOCKED], 'claimed' => %w[CLAIMED], 'discarded' => %w[DISCARDED] }.freeze

  def execute(**opts)
    rows = query(opts).to_a
    return empty_text(opts) if rows.empty?

    listed = rows.first(limit_of(opts[:limit]))
    "【线索池：符合条件 #{rows.size} 家，列出 #{listed.size} 家】\n#{listed.map { |l| "— #{line_for(l)}" }.join("\n")}"
  end

  private

  # 同一家公司常有好几个联系人，按公司去重再列——否则一屏全是同一家。
  def query(opts)
    filtered(scope.leads.where.not(company_name: nil), opts)
      .where("COALESCE((raw->>'screen_score')::int, 0) >= ?", score_of(opts[:min_score]))
      .order(Arel.sql("(raw->>'screen_score')::int DESC NULLS LAST"))
      .limit(200).uniq(&:company_name)
  end

  def filtered(base, opts)
    base = base.where(status: STATUS_SETS.fetch(opts[:status].to_s, STATUS_SETS['open'])) unless opts[:status] == 'all'
    base = base.where(country: market_name(opts[:market])) if opts[:market].present?
    base = base.where(crm_lead_campaign_id: campaign_ids(opts[:campaign])) if opts[:campaign].present?
    base
  end

  def line_for(lead)
    raw = lead.raw
    bits = ["ID #{lead.id}｜#{lead.company_name}", lead.domain.presence, lead.country.presence,
            lead.industry.presence, "匹配度 #{raw['screen_score'] || '—'}", why_text(raw), contact_text(lead)]
    bits.compact.join('｜')
  end

  # 背调读过官网，比初筛看名字猜的硬气得多，有背调就用背调那句。
  def why_text(raw)
    note = raw.dig('bg', 'note')
    return "背调：#{note.to_s.truncate(40)}" if note.present?

    raw['screen_why'].to_s.truncate(20).presence
  end

  # 邮箱解锁要花 Apollo 积分，所以这里只说有没有，不替人解。
  def contact_text(lead)
    return "联系人 #{lead.person_name}（#{lead.email}）" if lead.email.present?
    return "有联系人 #{lead.person_name}，邮箱未解锁" if lead.person_name.present?

    '暂无联系人'
  end

  def campaign_ids(keyword)
    scope.lead_campaigns.where('name ILIKE ?', "%#{keyword}%").pluck(:id)
  end

  # 市场代码和线索上存的国家名不是一回事（GERMANY vs Germany）。
  MARKET_NAMES = { 'USA' => 'USA', 'UK' => 'UK', 'GERMANY' => 'Germany', 'FRANCE' => 'France',
                   'ITALY' => 'Italy', 'SPAIN' => 'Spain' }.freeze

  def market_name(market)
    key = market.to_s.strip.upcase
    MARKET_NAMES[key] || market.to_s.strip.capitalize
  end

  def score_of(value) = value.to_s.strip.empty? ? DEFAULT_SCORE : value.to_i.clamp(0, 100)

  def limit_of(value)
    n = value.to_i
    (n.positive? ? n : 15).clamp(1, MAX_LIMIT)
  end

  def empty_text(opts)
    "没有符合条件的线索（#{opts[:market].presence || '全部市场'}，匹配度 ≥ #{score_of(opts[:min_score])}）。"
  end
end
