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
    when 'name_not_found' then name_not_found_text(result[:name])
    when 'name_candidates' then candidates_text(result[:name], result[:candidates])
    when 'no_site' then no_site_text(result[:domain])
    else ok_text(result)
    end
  end

  private

  # 名字只对上个大概：把候选摆出来让人挑，**不要替他选一个就往下查**。
  # 企业库的按名搜索是模糊匹配，「B&B Group」返回的第一条是 B. Braun（德国医疗集团），
  # 照着查会得到一份详尽可信、却完全是另一家公司的背调。
  def candidates_text(name, candidates)
    rows = Array(candidates).map do |c|
      "· #{c[:name]}（#{c[:domain]}）#{[c[:city], c[:country]].compact_blank.join(' · ')}"
    end
    "企业库里没有名字正好叫「#{name}」的公司，这几家只是沾边：\n#{rows.join("\n")}\n" \
      '是其中哪一家？把它的域名发我，我按域名重查。都不是的话，给我对方的公司邮箱或官网更准。'
  end

  # 按公司名查企业库也查不到。别只回一句「查不到」——告诉他换什么线索能查出来，
  # 否则这条就断在这儿了（生产上真发生过：只有公司名和人名，助手直接转头去查系统内部）。
  def name_not_found_text(name)
    "企业库里没有叫「#{name}」的公司。换对方的**公司邮箱**（@后面那段）或**官网网址**再查一次，" \
      '这两个比公司名准得多；如果手上只有公司名，多半是名字拼写或简称对不上。'
  end

  # 域名解析出来了但官网抓不动（纯前端渲染、防爬、或者站点已经没了），企业库也没这家。
  def no_site_text(domain)
    "找到域名 #{domain}，但官网抓不到正文，企业库里也没有这家——" \
      "可能是站点做了防爬、整站前端渲染，或者这个域名根本没在用。\n" \
      "#{dup_line(domain)}\n" \
      '建议：让业务员把对方官网上「关于我们」或「Impressum」那一页的网址直接发过来，我按那个地址查。'
  end

  # profile 里除 company_name/legit 外的字段，按这个顺序摆出来。
  # 2026-10-30 之前这里只给模型 business 和 note（note 还截到 400 字），
  # industry / size_hint / country 查到了却丢掉，Apollo 那一整块更是一个字都没传——
  # 结果就是助手只能说「这家是做什么的」，说不出法人实体、规模、负责人，
  # 写开发信时也就没东西可用。
  PROFILE_FIELDS = [
    ['主营', 'business'], ['行业', 'industry'], ['规模线索', 'size_hint'],
    ['国家/地区', 'country'], ['法定实体', 'legal_entity'], ['地址', 'address'],
    ['负责人', 'management'], ['他们在卖', 'product_lines'],
    ['可能向我们采购', 'buying_categories']
  ].freeze

  # 「未提及」是提示词要求模型在官网没写时填的占位，别当成内容报给业务员。
  BLANK_VALUES = ['未提及', '未知', '-', 'N/A', 'n/a'].freeze

  def ok_text(result)
    profile = result[:profile] || {}
    ([headline(profile, result)] +
      [matched_by_name_line(result)] +
      field_lines(profile) +
      ["官网：#{result[:domain]}"] +
      enrichment_lines(result[:enrichment]) +
      [mismatch_line(result[:enrichment_warning]), note_line(profile),
       dup_line(result[:domain])]).compact_blank.join("\n")
  end

  # 是按公司名找出来的，就说清楚「我按哪一家查的、还有哪几家同名」——
  # 同名公司很常见，不讲明白等于替业务员做了一个他不知道的选择。
  def matched_by_name_line(result)
    return nil if result[:matched_by_name].blank?

    picked = result[:picked_candidate] || {}
    others = Array(result[:candidates]).drop(1).map { |c| "#{c[:name]}（#{c[:domain]}）" }
    line = "（按公司名「#{result[:matched_by_name]}」在企业库里匹配到 #{picked[:name]}，域名 #{picked[:domain]}）"
    others.any? ? "#{line}\n同名的还有：#{others.join('、')}——不是这家就换个域名重查。" : line
  end

  def headline(profile, result)
    "【#{profile['company_name'].presence || result[:domain]}】#{LEGIT_LABELS[profile['legit']] || '—'}"
  end

  def field_lines(profile)
    PROFILE_FIELDS.filter_map do |label, key|
      value = profile[key].to_s.strip
      "#{label}：#{clip(value, 500)}" if value.present? && BLANK_VALUES.exclude?(value)
    end
  end

  # Apollo 按域名匹配偶尔会命中同名但不是同一家的公司。服务层已经把对不上的迹象算出来了，
  # 不报给模型，它就会拿着另一家公司的员工数和营收去写开发信。
  def mismatch_line(warning)
    return nil if warning.blank?

    "⚠️ 企业库这条记录可能不是同一家公司（#{Array(warning[:reasons]).join('；')}），" \
      '上面「企业库补充」里的数字请先核实再用。'
  end

  def note_line(profile)
    profile['note'].present? ? "判断：#{clip(profile['note'], 800)}" : nil
  end

  # Apollo 企业库：员工数、营收、成立年份这些官网通常不写，但判断对方分量时最有用。
  ENRICH_FIELDS = [
    ['企业库登记名', :name], ['员工数', :employees], ['营收', :revenue],
    ['成立年份', :founded_year], ['所在地', :city], ['LinkedIn', :linkedin], ['电话', :phone]
  ].freeze

  def enrichment_lines(enrichment)
    return [] if enrichment.blank?

    lines = ENRICH_FIELDS.filter_map do |label, key|
      value = enrichment[key].to_s.strip
      "#{label}：#{value}" if value.present?
    end
    keywords = Array(enrichment[:keywords]).compact_blank
    lines << "业务关键词：#{keywords.join('、')}" if keywords.any?
    lines.any? ? ['—— 企业库补充 ——'] + lines : []
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
