# 全公司已经验证过的搜索词库。
#
# 为什么要有：关键词是这个功能的胜负手——同一个任务里 medientechnik 通过率 100%、
# kids tablet 7%，差十四倍（2026-11-08 实测）。而这些经验现在只活在单个任务里，
# 新人建任务还是从零开始写 kids tablet，然后得出「这功能不准」的结论。
#
# 词库不是另存一份，而是**从已有任务的评级里现算**（见 Crm::KeywordGrade）：
# 另存一份就会和真实战绩脱节，而这张表的全部价值就在于它是战绩。
class Crm::LeadKeywordLibrary
  # 只推荐这两档。弱词和废词不进库——推荐一个已知不行的词，比不推荐更糟。
  USABLE_GRADES = %w[proven usable].freeze

  def initialize(account:)
    @account = account
  end

  # { 市场 => [{ text:, grade:, companies:, passed:, rate: }] }，按通过率排。
  def by_market
    rows.group_by { |r| r[:market] }
        .transform_values { |list| list.sort_by { |r| [-r[:rate], -r[:companies]] }.first(20) }
  end

  private

  def rows
    campaigns.flat_map { |campaign| campaign_rows(campaign) }
             .group_by { |r| [r[:market], r[:text]] }
             .map { |_key, dups| merge(dups) }
  end

  # 同一个词在多个任务里都用过：战绩合并，别让一个任务的坏运气埋掉它。
  def merge(dups)
    companies = dups.sum { |d| d[:companies] }
    passed = dups.sum { |d| d[:passed] }
    best = dups.max_by { |d| USABLE_GRADES.index(d[:grade]) ? -USABLE_GRADES.index(d[:grade]) : -9 }
    { market: best[:market], text: best[:text], grade: best[:grade],
      companies: companies, passed: passed,
      rate: companies.zero? ? 0 : (100.0 * passed / companies).round }
  end

  def campaign_rows(campaign)
    stats = Crm::KeywordGrade.new(campaign: campaign).send(:stats)
    Array(campaign.keywords).filter_map do |row|
      next unless USABLE_GRADES.include?(row['grade'])

      key = [row['market'].to_s, row['text'].to_s]
      s = stats[key] || { companies: 0, passed: 0 }
      { market: row['market'], text: row['text'], grade: row['grade'],
        companies: s[:companies], passed: s[:passed] }
    end
  end

  # 只收共享任务的词：不共享的任务是人家的私活，战绩不该被全公司拿去用。
  def campaigns
    @account.crm_lead_campaigns.where(shared: true)
  end
end
