# AI 客户背调：邮箱/域名/公司名 → 抓官网 + Apollo 企业库，顺带查库里有没有重复建档。
#
# 这个能力旧「AI 助手」里有（ai#ask 的 background_check 意图），换 agent 后断了。
# 外贸最常见的场景就是收到一封陌生询盘：先问「这家靠谱吗、我们是不是已经有人在跟」。
#
# 查重只报数量和**自己权限范围内**的那几条：别人私海里的客户名不能借 AI 看到，
# 但「系统里已经有 3 条同域名记录」这个数必须说——不然两个业务员撞同一个客户。
class Crm::Agent::Tools::CompanyLookup < Crm::Agent::Tools::Base
  description '对一家公司做背景调查：输入对方邮箱、公司域名或公司名，抓官网和企业库判断是否真实在营，并查系统里是否已有同域名客户（防撞单）。适合处理陌生询盘。'
  param :query, desc: '对方邮箱、公司域名、网址或公司名'

  LEGIT_LABELS = {
    'real' => '看起来是正常运营的真实公司', 'suspicious' => '信息可疑，建议谨慎核实',
    'unknown' => '信息不足，难以判断'
  }.freeze

  def execute(query:)
    q = query.to_s.strip
    return '请给出对方的邮箱、公司域名或公司名。' if q.blank?

    result = Crm::CompanyLookupService.new(account: scope.account).call(query: q)
    case result[:status]
    when 'invalid' then "「#{q}」不是有效的邮箱/域名/公司名。"
    when 'public_domain' then "#{result[:domain]} 是 gmail/qq 这类公共邮箱域名，据此判断不了公司背景。"
    when 'no_site' then "找到域名 #{result[:domain]}，但没抓到可用的公司信息。#{dup_line(result[:domain])}"
    else ok_text(result)
    end
  end

  private

  def ok_text(result)
    p = result[:profile] || {}
    lines = ["【#{p['company_name'].presence || result[:domain]}】#{LEGIT_LABELS[p['legit']] || '—'}"]
    lines << "主营：#{p['business']}" if p['business'].present?
    lines << "官网：#{result[:domain]}"
    lines << clip(p['note'], 400) if p['note'].present?
    lines << dup_line(result[:domain])
    lines.compact_blank.join("\n")
  end

  # 同域名查重：总数按全账户算（撞单预警要准），明细只列这个人看得到的。
  def dup_line(domain)
    return nil if domain.blank?

    all = scope.account.crm_customers.where('LOWER(contact_email) LIKE ?', "%@#{domain.downcase}")
    total = all.count
    return '系统里还没有同域名的客户记录。' if total.zero?

    mine = scope.customers.where(id: all.select(:id)).limit(5)
                .map { |c| "#{c.name}（归属 #{c.account_owner&.name || '未分配'}）" }
    "⚠️ 系统里已有 #{total} 条同域名客户记录，注意撞单。" \
      "#{mine.any? ? "你能看到的：#{mine.join('、')}" : '这些记录不在你的权限范围内，建档前先问一下。'}"
  end
end
