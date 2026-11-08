# 给线索排一个 AI 背调：去读公司官网 + 查企业库 + 验欧盟税号。
#
# 背调是线索池上最硬的那个信号——初筛只看公司名和域名猜，背调是真读了官网。
# 一次要跑十几二十秒，所以这里只**排队**，不等它跑完；跑完结果自己落到线索上。
class Crm::Agent::Tools::LeadBgCheck < Crm::Agent::Tools::Base
  writes_data

  description '给新客开发的线索排 AI 背调（读官网+查企业库+验欧盟税号）。排队执行，十几秒后结果会出现在线索上。'
  param :lead_ids, desc: '线索ID，多条用逗号隔开'

  # 一次最多排几条。背调跑在最低优先级队列上，一口气塞几百条会把队列堵住。
  MAX_BATCH = 20

  def execute(lead_ids:)
    leads = scope.leads.where(id: lead_ids.to_s.scan(/\d+/).map(&:to_i)).where.not(domain: nil)
    return '这些线索没有公司域名，背调查不了。' if leads.empty?

    picked = leads.to_a.uniq(&:domain).first(MAX_BATCH)
    picked.each { |lead| enqueue(lead) }
    "已排 #{picked.size} 条背调：#{picked.map(&:company_name).join('、')}。" \
      '十几秒后在新客开发页面刷新就能看到结论，也可以回头问我。'
  end

  private

  def enqueue(lead)
    lead.update_columns(raw: lead.raw.merge('bg_running_at' => Time.current.iso8601)) # rubocop:disable Rails/SkipsModelValidations
    Crm::LeadBgCheckJob.perform_later(lead.id)
  end
end
