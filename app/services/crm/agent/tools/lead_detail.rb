# 一条线索的全部家底：初筛理由、背调结论、公司资料、欧盟税号、联系人。
#
# 线索池那个工具一行只放得下一句话，而「这家到底值不值得打」要看的是背调正文——
# AI 真读过官网，比初筛看公司名猜的硬气得多。
class Crm::Agent::Tools::LeadDetail < Crm::Agent::Tools::Base
  description '看一条新客开发线索的详细情况：AI 初筛理由、背调结论（真读过官网）、公司资料、税号、联系人。'
  param :lead_id, type: 'integer', desc: '线索ID（线索池里每行开头那个）'

  def execute(lead_id:)
    lead = scope.leads.find_by(id: lead_id)
    return "看不到 ID #{lead_id} 这条线索。" if lead.nil?

    ([header(lead)] + body(lead)).compact.join("\n")
  end

  private

  def header(lead)
    "【#{lead.company_name}｜#{lead.country.presence || '国家未知'}｜匹配度 #{lead.raw['screen_score'] || '—'}】"
  end

  def body(lead)
    raw = lead.raw
    [domain_line(lead), screen_line(raw), *bg_lines(raw), org_line(raw['org']),
     contact_line(lead), source_line(raw), dup_line(lead)]
  end

  def domain_line(lead)
    return nil if lead.domain.blank?

    url = Crm::SiteUrl.for(domain: lead.domain, website: lead.raw.dig('org', 'website'),
                           bg_url: lead.raw.dig('bg', 'url'))
    "官网：#{url}"
  end

  VERDICTS = { 'yes' => '像买家', 'no' => '不像买家', 'unsure' => '看不出' }.freeze

  def screen_line(raw)
    return nil if raw['screen'].blank?

    "AI 初筛：#{VERDICTS[raw['screen']] || raw['screen']}#{" · #{raw['screen_why']}" if raw['screen_why'].present?}"
  end

  # 背调是这个工具的主菜：status 不是 ok 说明官网没抓到，得说清楚，
  # 不然模型会把「没查到」说成「查了没问题」。
  def bg_lines(raw)
    bg = raw['bg']
    return ['背调：还没做（可以叫我去排一个）'] if bg.blank?
    return ["背调：官网没抓到（#{bg['site_status'] || bg['status']}），只能靠公开资料判断"] if bg['status'] != 'ok'

    ["背调结论：#{bg['note']}", bg['business'].present? ? "主营：#{bg['business']}" : nil,
     bg['buying'].present? ? "可能采购：#{bg['buying']}" : nil,
     bg['size'].present? ? "规模：#{bg['size']}" : nil, vat_line(bg)].compact
  end

  # 欧盟官方验过的税号是三方证据里唯一官方的那一方，值得单独摆一行。
  def vat_line(check)
    return nil if check['vat'].blank?

    status = check['vat_status'] == 'valid' ? '欧盟官方已验证' : "官方验证未通过（#{check['vat_status']}）"
    "增值税号 #{check['vat']}·#{status}"
  end

  def org_line(org)
    return nil if org.blank?

    bits = [org['employees'] && "#{org['employees']} 人", org['revenue'] && "营收 #{org['revenue']}",
            org['retail'] && "#{org['retail']} 家门店", org['phone'], org['linkedin'] && '有领英']
    bits.compact.any? ? "公司资料：#{bits.compact.join('｜')}" : nil
  end

  def contact_line(lead)
    return '联系人：暂无' if lead.person_name.blank?
    return "联系人：#{lead.person_name}（#{lead.title}）· #{lead.email}" if lead.email.present?

    "联系人：#{lead.person_name}（#{lead.title}）· 邮箱未解锁（解锁要花 Apollo 积分，得人在界面上点）"
  end

  def source_line(raw)
    return nil if raw['matched_keyword'].blank?

    tag = raw['apollo_tag']
    word = tag.present? && tag != raw['matched_keyword'] ? "#{raw['matched_keyword']}（实际按「#{tag}」搜）" : raw['matched_keyword']
    "搜索词：#{word}"
  end

  def dup_line(lead)
    hit = Crm::LeadDuplicate.new(account: scope.account)
                            .find(domain: lead.domain, company_name: lead.company_name)
    return nil if hit.nil?

    "⚠️ 这家已经是我们客户了（#{hit.customer_name}，归属 #{hit.owner_name || '公海'}），别重复开发。"
  end
end
