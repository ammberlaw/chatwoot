# 新客开发的效果表：每个搜索词最后到底带来了什么。
#
# 这是整套获客里同类工具做不到的一件事——它们的链路到「发出开发信」就断了，
# 发出去之后成没成交看不见。我们的线索建档之后就是同一个库里的客户，
# 从搜索词一路追到成交额只是一条 SQL。
class Crm::Agent::Tools::LeadOutcomes < Crm::Agent::Tools::Base
  description '新客开发的效果表：哪个搜索词带来了客户和成交，哪个搜了一堆白搜。按提问人自己的数据权限范围算。'
  param :limit, type: 'integer', desc: '最多列几个搜索词，默认 12', required: false

  def execute(limit: 12)
    stats = Crm::LeadOutcomeStats.new(campaigns: scope.lead_campaigns)
    rows = stats.by_keyword
    return '还没有搜索记录，效果表是空的。' if rows.empty?

    ["【新客开发效果】#{summary_text(stats.summary)}",
     *rows.first(limit.to_i.clamp(1, 30)).map { |r| "— #{row_text(r)}" },
     barren_text(stats)].compact.join("\n")
  end

  private

  def summary_text(sum)
    "#{sum[:keywords]} 个搜索词，搜回 #{sum[:leads]} 条线索，建档 #{sum[:claimed]} 个客户，" \
      "成交 #{sum[:won]} 单#{" 共 #{money(sum[:deal_rmb] * 1_000_000)}" if sum[:deal_rmb].to_i.positive?}"
  end

  def row_text(row)
    bits = ["#{row[:keyword]}：线索 #{row[:leads]}"]
    bits << "初筛通过 #{row[:screen_rate]}%" if row[:screen_rate]
    bits << "建档 #{row[:claimed]}" if row[:claimed].positive?
    bits << "成交 #{money(row[:deal_rmb] * 1_000_000)}" if row[:deal_rmb].to_i.positive?
    bits.join('｜')
  end

  # 白搜的词单独点名：这张表真正能改的动作就是「换掉这几个词」。
  def barren_text(stats)
    barren = stats.barren_keywords.pluck(:keyword)
    return nil if barren.empty?

    "搜了不少却一个都没建档的：#{barren.join('、')}——下轮该换掉的就是它们。"
  end
end
