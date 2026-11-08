# 背调做完之后，拿背调结论**回头重判**初筛分数。
#
# 为什么必须有这一步：初筛跑在背调之前（那是故意的——先筛掉一多半，别为不是买家的
# 公司白花 Apollo 调用），所以它判的时候只看得见公司名、域名、行业代码。
# 背调是十几秒后才回来的，读了官网、看了法律页，结论硬得多——但没人拿它改分。
#
# 后果实测（2026-11-08，任务 6/7/8）：399 家判 yes 的公司里有 **119 家（30%）**
# 背调明说「属于同行/竞争对手/品牌方渠道商」，分数却还挂着 70 分以上，照样排在第一页。
# 业务员看到的「最匹配的那批」，三成是错的。
#
# 顺带解 unsure：unsure 的意思是「只看名字看不出」，而背调恰恰补上了看不出的那部分。
class Crm::LeadRescreen
  # 一批送多少家给模型。和 Crm::LeadScreener::BATCH 一个量级即可。
  BATCH = 30
  # 一轮最多重判几家，防一次把几千条全推给模型。
  MAX_PER_RUN = 150

  def initialize(campaign:)
    @campaign = campaign
    @account = campaign.account
  end

  # 返回 { 重判家数, 降级家数 }。
  def call
    companies = pending.to_a.uniq(&:company_name).first(MAX_PER_RUN)
    return { judged: 0, downgraded: 0 } if companies.empty?

    downgraded = companies.each_slice(BATCH).sum { |batch| judge(batch) }
    { judged: companies.size, downgraded: downgraded }
  end

  # 做过背调、还没拿背调重判过的。已建档/已丢弃的不碰——人动过的，机器不许翻案。
  def pending
    @account.crm_leads.where(crm_lead_campaign_id: @campaign.id)
            .where(status: %w[FOUND UNLOCKED])
            .where("raw ? 'bg'").where.not("raw ? 'rescreened_at'")
            .where("raw->'bg'->>'status' = 'ok'")
  end

  private

  def judge(batch)
    verdicts = Crm::LeadScreener.verdicts_for(
      account: @account, items: batch.map { |lead| item_for(lead) },
      product_hint: @campaign.product_hint, criteria: @campaign.screen_criteria
    )
    batch.sum { |lead| apply(lead, verdicts[lead.company_name]) }
  end

  def item_for(lead)
    org = lead.raw['org'] || {}
    { name: lead.company_name, domain: lead.domain, industry: lead.industry,
      revenue: org['revenue'], retail: org['retail'], listed: org['listed'],
      bg: bg_text(lead.raw['bg']) }
  end

  # 摆给模型的背调摘要。结论那句最重要，主营和可能采购补充语境。
  def bg_text(check)
    [check['note'], check['business'], check['buying'].present? ? "可能采购：#{check['buying']}" : nil]
      .compact_blank.join('；').truncate(400)
  end

  # 返回 1 表示这家被降级了（分数掉了或从 yes 变成非 yes），用于汇报。
  def apply(lead, verdict)
    return 0 if verdict.blank?

    before = lead.raw['screen_score'].to_i
    stamp(lead, verdict)
    dropped = verdict[:score].to_i < before || (lead.raw['screen'] == 'yes' && verdict[:verdict] != 'yes')
    dropped ? 1 : 0
  end

  # 同一家公司名下的几个联系人一起改——口径同背调的写回，不然同一家会自相矛盾。
  def stamp(lead, verdict)
    @account.crm_leads.where(crm_lead_campaign_id: @campaign.id, company_name: lead.company_name)
            .where(status: %w[FOUND UNLOCKED]).find_each do |row|
      row.update_columns(raw: row.raw.merge( # rubocop:disable Rails/SkipsModelValidations
        'screen' => verdict[:verdict], 'screen_why' => verdict[:why],
        'screen_score' => verdict[:score], 'rescreened_at' => Time.current.iso8601
      ))
    end
  end
end
