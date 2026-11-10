# 给一条线索抓联系人。**领取那一刻才抓**，不在搜索阶段抓。
#
# 为什么挪到这里（2026-11-09）：搜索阶段挨家抓联系人，一轮下来 3048 家公司抓了
# 1516 个联系人、烧掉 2157 个 Apollo credits，而业务员真正解锁用上的只有 2 个。
# 更糟的是其中 963 个（64%）抓在 50 分以下的公司上——那些在列表里是沉底的，
# 没人会翻到；另有 452 个抓在初筛判「不是买家」的公司上（漏判的那批先抓了才补判）。
#
# 改成领取时抓：只给业务员真打算跟的公司花钱。持有上限（Crm::Lead::HOLD_LIMIT）
# 天然把单人消耗封在 60 家以内，所以暂不另设配额——观察一轮再说。
class Crm::LeadContactFetch
  PEOPLE_PER_COMPANY = 3

  # 优先找这些岗位的人。搜出一堆工程师和前台没用，要找拍板买的。
  # 第一档：采购口。主力市场在欧洲，所以带上当地职位词——
  # 德国中小企业的采购岗常常就写 Einkauf / Einkaufsleiter，不写英文。
  TARGET_TITLES = ['purchasing manager', 'procurement manager', 'buyer',
                   'sourcing manager', 'category manager', 'owner', 'ceo',
                   'head of purchasing', 'purchasing director', 'procurement director',
                   'einkaufsleiter', 'einkauf', 'responsable achats', 'acheteur',
                   'responsabile acquisti', 'director de compras', 'inkoop'].freeze

  # 第二档：采购口一个人都搜不到时才用。
  # 2026-11-07 实测：42 家值得跟的公司里 19 家（45%）按采购职位搜回来是空的——
  # 不是没人，是小公司根本没人挂「采购经理」的头衔，老板自己拍板。
  # ⚠️ 绝不退到「完全不限职位」：那样搜回来的头两个是 HR 和用户体验总监。
  FALLBACK_TITLES = ['managing director', 'geschäftsführer', 'general manager',
                     'president', 'vice president', 'country manager',
                     'sales director', 'head of sales', 'business development manager',
                     'product manager', 'operations manager'].freeze

  def initialize(lead, user: nil)
    @lead = lead
    @account = lead.account
    # scene/user 进 Apollo 台账（Crm::ApolloCall）：哪一笔是谁领取时花的，要查得出来。
    @client = Crm::ApolloClient.new(account: @account, scene: 'contact_fetch', user: user)
  end

  # 返回抓到的联系人数。0 = 这家搜不到人（调用方据此决定要不要退回池子）。
  #
  # 第一个人填回这条线索本身，其余的另建——线索的粒度本来就是「一个联系人一条」，
  # 而领取是按公司整组领的（见 Crm::LeadClaim#stamp），所以新建的几条同样归他。
  def call
    return 0 if @lead.domain.blank? || !@client.configured?
    return 0 if @lead.person_name.present?

    people = find_people
    return 0 if people.empty?

    fill_first(people.first)
    people.drop(1).sum { |person| clone_for(person) } + 1
  end

  private

  def find_people
    people = people_by_titles(TARGET_TITLES)
    people.presence || people_by_titles(FALLBACK_TITLES)
  end

  # 没邮箱的留不下来（解锁不出东西），但 Apollo 按返回的记录计费，
  # 这一笔已经花掉了。请求侧能不能预过滤要等额度恢复后实测。
  def people_by_titles(titles)
    @client.search_people(domain: @lead.domain, titles: titles, limit: PEOPLE_PER_COMPANY)
           .select { |person| person[:has_email] }
  end

  def fill_first(person)
    @lead.update!(person_attrs(person).merge(raw: @lead.raw.merge('has_email' => person[:has_email])))
  end

  # 同一家公司的第二、第三个人各建一条——线索的粒度本来就是「一个联系人一条」。
  # 归属跟着第一条走：领取是整家公司一起领的（Crm::LeadClaim#stamp）。
  def clone_for(person)
    @account.crm_leads.create!(
      @lead.attributes.slice('crm_lead_campaign_id', 'company_name', 'domain', 'country',
                             'industry', 'status', 'owner_id', 'claimed_at', 'dup_customer_id')
           .merge(person_attrs(person).stringify_keys)
           .merge('raw' => @lead.raw.merge('has_email' => person[:has_email]))
    )
    1
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[LeadContactFetch] lead=#{@lead.id} 建联系人失败: #{e.message}")
    0
  end

  # 字段对齐 Crm::LeadSearchRunner#lead_attrs：搜索阶段原本就是这么填的。
  # has_email 在 raw 里（不是列），别写成 email_status——Apollo 搜索阶段不给那个字段。
  def person_attrs(person)
    { person_name: person[:name], title: person[:title], apollo_person_id: person[:apollo_id] }
  end
end
