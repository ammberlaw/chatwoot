# 给每个搜索词评级，并把结论写回任务的关键词上。
#
# 为什么要评级：一个任务攒到四五十个词之后，人已经分不清哪些还在干活。
# 实测（2026-11-08，五个任务 102 个词）：**28 个弱词吃掉了 1520 条线索的额度**，
# 产出接近零；而真正的好词只有 19 个。不分级的话这些词会一直占着每轮的配额。
#
# 评级口径按**公司数**算，不按线索条数——同一家公司常有好几个联系人，
# 按条数算会把「搜到一家大公司的五个采购」当成五份战绩。
#
# ⚠️ 按 **(市场, 词)** 评，不按词本身。关键词是分市场存的，同一个英文词在美国搜砸了
# 不代表它在德国不行——按词评会把「在美国不行」的结论安到从没搜过的德国那一行上
# （2026-11-08 第一版就这么错的，任务 6 一口气判出 56 个废词）。
class Crm::KeywordGrade
  # 判死的最低样本。6 家全军覆没还说明不了什么（基准通过率三成左右，
  # 六连零的概率有 18%）；10 家才降到 5% 以下。
  DEAD_MIN = 10
  # 搜得多却几乎不出货的，也算废。
  BIG_SAMPLE = 25
  BIG_SAMPLE_RATE = 5
  # 能下结论的最低样本。
  JUDGE_MIN = 6
  PROVEN_RATE = 25
  WEAK_RATE = 10

  GRADES = {
    'proven' => '好词', 'usable' => '可用', 'weak' => '弱词',
    'dead' => '废词', 'new' => '待观察'
  }.freeze

  def initialize(campaign:)
    @campaign = campaign
  end

  # { [市场, 搜索词] => 级别 }
  def grades
    @grades ||= stats.transform_values { |row| grade_for(row) }
  end

  # 把级别写回关键词行，返回各级别的词数。
  def stamp!
    rows = Array(@campaign.keywords).map do |row|
      row.merge('grade' => grades.fetch([row['market'].to_s, row['text'].to_s], 'new'))
    end
    @campaign.update!(keywords: rows)
    rows.group_by { |r| r['grade'] }.transform_values(&:size)
  end

  private

  def grade_for(row)
    return 'proven' if row[:claimed].positive?
    return 'dead' if dead?(row)
    return 'new' if row[:companies] < JUDGE_MIN

    rate = row[:rate]
    return 'proven' if rate >= PROVEN_RATE
    return 'weak' if rate < WEAK_RATE

    'usable'
  end

  # 两种死法：搜够了一个都不过初筛；或者搜了一大堆、通过率低到可以忽略。
  def dead?(row)
    return true if row[:companies] >= DEAD_MIN && row[:passed].zero?

    row[:companies] >= BIG_SAMPLE && row[:rate] < BIG_SAMPLE_RATE
  end

  # { 词 => { companies:, passed:, claimed:, rate: } }
  def stats
    @stats ||= begin
      rows = @campaign.leads.where.not(company_name: nil)
                      .pluck(Arel.sql("raw->>'market'"), Arel.sql("raw->>'matched_keyword'"),
                             :company_name, Arel.sql("raw->>'screen'"), :status)
      rows.group_by { |r| [r[0].to_s, r[1].to_s] }
          .reject { |key, _| key.last.empty? }
          .transform_values { |group| summarize(group) }
    end
  end

  def summarize(group)
    companies = group.pluck(2).uniq.size
    passed = group.select { |r| r[3] == 'yes' }.pluck(2).uniq.size
    claimed = group.select { |r| r[4] == 'CLAIMED' }.pluck(2).uniq.size
    { companies: companies, passed: passed, claimed: claimed,
      rate: companies.zero? ? 0 : (100.0 * passed / companies).round }
  end
end
