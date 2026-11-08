# 获客效果:每个搜索词最后到底带来了什么。
#
# 这是整套获客里**唯一一件同类工具做不到的事**——它们的链路到「发出开发信」就断了,
# 发出去之后成没成交,它们看不见。而线索建档之后人就进了同一个库,
# 从搜索词一路追到成交额对我们只是一条 SQL。
#
# 做出来干两件事:
#   ① 给人看:哪个词值得继续投,哪个词搜了一堆一个都没建档
#   ② 喂回给 AI:下一轮生成关键词时带上这张表(见 Crm::LeadProfileBuilder#collect_facts),
#      用得越久越准
class Crm::LeadOutcomeStats
  # 判定「这个词是白搜了」的最低样本量。搜了三条没建档说明不了什么。
  BARREN_MIN_LEADS = 8
  # 配额权重的先验（见 screen_weights）：没搜过的词按 1/5 的通过率起步。
  PRIOR_YES = 1
  PRIOR_TOTAL = 5
  # 再差的词也留一点额度——通过率低也可能是初筛当时判歪了，不能一棍子打死。
  MIN_WEIGHT = 0.05

  # campaigns 传的是**已经按负责人收口过的**任务集合——业务员只看自己的效果,
  # 管理员看全部(口径同列表页)。
  def initialize(campaigns:)
    @campaigns = campaigns
  end

  # [{ keyword:, leads:, claimed:, won:, deal_rmb: }]，按成交额排。
  def by_keyword
    @by_keyword ||= leads_by_keyword.map { |keyword, leads| row_for(keyword, leads) }
                                    .sort_by { |r| [-r[:deal_rmb], -r[:claimed], -r[:leads]] }
  end

  # 整体一句话:搜了多少、建了多少档、成了多少单。
  def summary
    rows = by_keyword
    {
      keywords: rows.size,
      leads: rows.sum { |r| r[:leads] },
      claimed: rows.sum { |r| r[:claimed] },
      won: rows.sum { |r| r[:won] },
      deal_rmb: rows.sum { |r| r[:deal_rmb] }
    }
  end

  # 真带来过客户的搜索词——这几个才值得喂回给模型。
  # 先按成交额、没成交的按建档数排,成交数据攒起来之前建档数就是最好的信号。
  def proven_keywords(limit: 8)
    by_keyword.select { |r| r[:claimed].positive? }.first(limit)
  end

  # 搜了不少、**既没建档也一条都没过初筛**的——下轮该换掉的就是它们。
  #
  # ⚠️ 不能只看建档数。建档要等业务员点，比搜索慢好几周，只看它会把
  # 「刚搜回一批好公司、还没人看」的词判死：2026-11-08 实测 toys and games wholesaler
  # 初筛通过率 34%（全场最高），却因为还没人建档被列进「白搜该换掉」。
  # 初筛通过率是当轮就有的信号，过得了说明方向对，给它时间。
  def barren_keywords(min_leads: BARREN_MIN_LEADS, limit: 8)
    by_keyword.select { |r| r[:claimed].zero? && r[:screened].zero? && r[:leads] >= min_leads }
              .sort_by { |r| -r[:leads] }.first(limit)
  end

  # 每个搜索词的配额权重（0.05–1）。给 Crm::LeadCompanyCollector 分配额用。
  #
  # 为什么不平均分：同一个任务里各词的初筛通过率能差到 35% vs 0%
  # （2026-11-08 实测：toys 34 家过 12 家，technology supplier 23 家过 0 家）。
  # 平均分等于把一半的额度浇在已知不长东西的地里。
  #
  # 没搜过的词按 PRIOR 给（拉普拉斯平滑）：新词要有机会证明自己，
  # 但也不该一上来就跟验证过的好词平起平坐。
  def screen_weights
    by_keyword.to_h do |row|
      [row[:keyword], ((row[:screened] + PRIOR_YES).to_f / (row[:leads] + PRIOR_TOTAL)).clamp(MIN_WEIGHT, 1.0)]
    end
  end

  private

  # 搜索词存在线索的 raw['matched_keyword'] 里（LeadSearchRunner 搜的时候记下的）。
  def leads_by_keyword
    Crm::Lead.where(crm_lead_campaign_id: @campaigns.select(:id))
             .select(:id, :raw, :crm_customer_id, :status)
             .group_by { |lead| lead.raw['matched_keyword'].presence }
             .except(nil)
  end

  def row_for(keyword, leads)
    claimed_ids = leads.filter_map(&:crm_customer_id).uniq
    deals = deal_totals(claimed_ids)
    passed = leads.count { |l| l.raw['screen'] == 'yes' }
    { keyword: keyword, leads: leads.size, claimed: claimed_ids.size,
      won: deals[:count], deal_rmb: deals[:rmb],
      # 初筛通过率：成交和建档要等人，初筛是**当轮就有**的质量信号。
      # 实测同一个任务里各词差到 35% vs 0%（2026-11-08），光凭它就能决定配额往哪倾。
      screened: passed, screen_rate: leads.empty? ? nil : (100.0 * passed / leads.size).round }
  end

  # 成交口径取客户档案上的累计成交(和客户列表、看板同一个数),
  # 不自己再算一遍订单——两处口径一旦走偏,没人说得清哪个对。
  def deal_totals(customer_ids)
    return { count: 0, rmb: 0 } if customer_ids.empty?

    micros = Crm::Customer.where(id: customer_ids).where('deal_order_count > 0')
                          .pluck(:deal_total_amount_micros)
    { count: micros.size, rmb: (micros.compact.sum / 1_000_000.0).round }
  end
end
