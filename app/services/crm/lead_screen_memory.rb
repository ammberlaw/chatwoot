# AI 初筛的「判例库」:业务员在线索池里点过的建档/丢弃，攒起来当下一轮的判断依据。
#
# 这是初筛会越用越准的地方——人本来就要在线索池里做这个动作，
# 系统只是把它记下来，不用谁额外填东西。
#
# ⚠️ 判例必须带**可泛化的特征**（行业、营收、门店数、国家），不能只给公司名。
# 2026-11-08 之前喂回去的是一行裸名字「Handelsblatt」——模型从名字里归纳不出
# 「哪一类该要」，只能记住「这个名字」。带上行业之后它才学得到「出版类不要」。
#
# ⚠️ 判例是**人点出来的**，点错了就会教错。所以它必须在界面上看得见
# （开发效果面板里那块「AI 已学到的判例」），而不是悄悄在后台生效。
class Crm::LeadScreenMemory
  # 带几条给模型。再多会把真正要判的名单挤到后面去。
  LIMIT = 12

  # 丢弃原因 → 给模型看的说法。业务员点一下就走，不打字（见线索池的丢弃菜单）。
  DISCARD_REASONS = {
    'RIVAL' => '是同行/竞争对手',
    'SIZE' => '规模不合适',
    'CATEGORY' => '品类不对',
    'EXISTING' => '已经在合作或已联系过',
    'COUNTRY' => '国家/地区不对',
    'UNREACHABLE' => '联系不上',
    'OTHER' => '其它'
  }.freeze

  def initialize(account:)
    @account = account
  end

  # { claimed: [...], rejected: [...] }，每条是 { name:, industry:, revenue:, retail:, country:, reason: }
  def examples
    @examples ||= { claimed: claimed_examples, rejected: rejected_examples }
  end

  # 从判例里归纳出的方向，摆在界面上给人看：倾向哪几类、排除哪几类。
  #
  # ⚠️ 同一个行业两边都出现过的，**两边都不算方向**。
  # 实测遇到过：HRS（系统集成）建了档，System Soft（系统集成）被丢掉——
  # 丢它的原因是「品类不对」，不是因为它是系统集成。
  # 这种情况下行业本身不是信号，硬摆出来只会让人困惑。
  def learned_directions
    yes = tally(examples[:claimed])
    no = tally(examples[:rejected])
    {
      prefer: yes.reject { |k, v| v <= no.fetch(k, 0) },
      avoid: no.reject { |k, v| v <= yes.fetch(k, 0) },
      reasons: examples[:rejected].filter_map { |e| DISCARD_REASONS[e[:reason]] }.tally
    }
  end

  # 拼给模型的那段话。一条判例都还没有时返回 nil（第一轮本来就没有）。
  def prompt_block
    lines = [
      block_for(examples[:claimed], '业务员建了档的（这类就是我们要的）'),
      block_for(examples[:rejected], 'AI 当时判「像买家」、业务员看过不要的（判错的方向）')
    ].compact
    return nil if lines.empty?

    "业务员以前的判断（**按特征归纳，不要只记公司名**）：\n#{lines.join("\n")}"
  end

  private

  def block_for(rows, title)
    return nil if rows.empty?

    "· #{title}：\n#{rows.map { |r| "    #{describe(r)}" }.join("\n")}"
  end

  # 一条判例长什么样：名字 + 行业 + 规模 + 国家 +（丢弃的话）为什么丢。
  def describe(row)
    bits = [row[:name]]
    bits << row[:industry] if row[:industry].present?
    bits << "营收 #{row[:revenue]}" if row[:revenue].present?
    bits << "门店 #{row[:retail]} 家" if row[:retail].to_i.positive?
    bits << row[:country] if row[:country].present?
    bits << "原因：#{DISCARD_REASONS[row[:reason]]}" if DISCARD_REASONS.key?(row[:reason])
    bits.join(' · ')
  end

  def tally(rows)
    rows.filter_map { |r| r[:industry].presence }.tally.sort_by { |_k, v| -v }.to_h
  end

  def claimed_examples
    rows_for(account_leads.where(status: 'CLAIMED'))
  end

  # 只取「AI 说像、人却丢掉」的——这才是纠正信号。
  # 已经是自家客户的那种丢弃排掉（dup_customer_id 不为空），人丢它不是因为不像买家。
  def rejected_examples
    rows_for(account_leads.where(status: 'DISCARDED', dup_customer_id: nil)
                          .where("raw->>'screen' = 'yes'"))
  end

  def rows_for(scope)
    scope.select(:company_name, :industry, :country, :raw).limit(LIMIT * 3)
         .uniq(&:company_name).first(LIMIT).map do |lead|
      org = lead.raw['org'] || {}
      { name: lead.company_name, industry: lead.industry, country: lead.country,
        revenue: org['revenue'], retail: org['retail'], reason: lead.raw['discard_reason'] }
    end
  end

  def account_leads
    Crm::Lead.where(account_id: @account.id).where.not(company_name: [nil, '']).order(id: :desc)
  end
end
