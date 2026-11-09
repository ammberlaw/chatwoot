# 线索池里的单条操作：解锁联系方式、建成客户、丢弃。
class Api::V1::Accounts::Crm::LeadsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_lead

  # 解锁真实邮箱。**这一步扣 Apollo credits**，所以做成人工点，不批量解。
  def unlock
    return render json: { error: '这条没有可解锁的联系人' }, status: :unprocessable_entity if @lead.apollo_person_id.blank?

    # 解锁 = 认领。没领就能解锁的话，共享池形同虚设——
    # 两个人对同一家各解锁一次，钱花两份、还撞单。
    taken = ensure_mine
    return render json: { error: taken }, status: :unprocessable_entity if taken.present?

    # 额度在**调 Apollo 之前**查。查晚了积分已经扣掉，再拦就只是拦了个寂寞。
    quota = Crm::ApolloQuota.new(account: Current.account).status_for(current_user)
    return render json: { error: quota.block_reason }, status: :unprocessable_entity unless quota.allowed?

    ok = Crm::LeadUnlock.call(@lead, current_user)
    return render json: { error: '没解锁到邮箱（Apollo 那边可能没有这个人的地址）' }, status: :unprocessable_entity unless ok

    render json: lead_json(@lead.reload)
  end

  # 从共享池里**领取**这条线索：保护期内归自己，别人看不见也领不走。
  # 和 claim（建档成客户）是两件事——领了只是占住跟进权，还没进客户库。
  def take
    result = Crm::LeadClaim.new(account: Current.account, user: current_user).call(@lead)
    return render json: { error: result.message }, status: :unprocessable_entity unless result.ok

    render json: lead_json(@lead.reload).merge(message: result.message)
  end

  # 放回池子。手上压满了（Crm::Lead::HOLD_LIMIT）又不想丢弃时用——
  # 丢弃是「这家不是买家」，放回是「我暂时跟不了」，两个含义不能混。
  def release
    return render json: { error: '这条不在你手上' }, status: :unprocessable_entity if @lead.holder_id != current_user.id

    Current.account.crm_leads.where(company_name: @lead.company_name, owner_id: current_user.id,
                                    status: %w[FOUND UNLOCKED])
           .update_all(owner_id: nil, claimed_at: nil, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    render json: lead_json(@lead.reload)
  end

  # 建成客户档案。撞到已有客户就不建、直接指过去（口径同建档页查重）。
  def claim
    # 建档 = 认领。同上：没领就能建档的话，池子拦不住任何人。
    taken = ensure_mine
    return render json: { error: taken }, status: :unprocessable_entity if taken.present?

    result = Crm::LeadToCustomer.call(@lead, current_user.id)
    render json: lead_json(@lead.reload).merge(
      duplicate: result.duplicate, customer_name: result.customer.name
    )
  end

  # 丢弃时带一个原因码。原因不是给人看的记录，是**给初筛学的方向**——
  # 没有原因，系统只能学到「这家不要」，学不到「这类不要」。
  # 做成一键选（见线索池的丢弃菜单），不让人打字。
  def discard
    reason = params[:reason].to_s.presence
    reason = nil unless Crm::LeadScreenMemory::DISCARD_REASONS.key?(reason)
    # 记下是谁丢的：丢弃会喂给 AI 初筛的判例库，一个人批量乱丢能把整套初筛教歪，
    # 查不出是谁就没法纠（也没法拦住「为了腾持有额度而清库存」）。
    @lead.update!(status: 'DISCARDED', discarded_by_id: current_user.id, discarded_at: Time.current,
                  raw: @lead.raw.merge({ 'discard_reason' => reason }.compact))
    render json: lead_json(@lead)
  end

  # 一键 AI 背调：抓官网 + Apollo 企业库，结果存回线索（同公司的几个联系人共用）。
  # 这是线索池上最该有的一个动作——AI 初筛只看公司名和域名猜，背调是真去读了官网。
  #
  # ⚠️ 名字必须以 ai_ 开头：实测一次要跑近 30 秒，靠 config/initializers/rack_timeout.rb
  # 末尾的 ai_* 通配吃到 90 秒放宽，否则会被 15 秒闸刀掐成裸 500。
  # 改成异步排队，不在请求里跑完。
  #
  # 同步跑的问题是占着 Web 线程 20~30 秒等外国网站，生产一共 15 个线程——
  # 五六个业务员同时点，三分之一的线程卡住，整个系统对所有人都变钝。
  # 而且让人盯着转圈半分钟本来就不该。
  # 现在点完立刻返回，前端轮询这条线索，跑完自己刷新。
  def ai_bg_check
    return render json: { error: '这条线索没有公司域名' }, status: :unprocessable_entity if @lead.domain.blank?

    @lead.update_columns(raw: @lead.raw.merge('bg_running_at' => Time.current.iso8601)) # rubocop:disable Rails/SkipsModelValidations
    # 手动这次走 low：一次只有一个，而且人在等。批量的走 deferred。
    Crm::LeadBgCheckJob.set(queue: :low).perform_later(@lead.id)
    # 背调回来之后拿结论重判一次分数（见 Crm::LeadRescreen）——
    # 初筛是在背调之前跑的，它当时看不见官网里的东西。
    Crm::LeadRescreenJob.set(wait: 1.minute).perform_later(@lead.crm_lead_campaign_id)
    render json: lead_json(@lead.reload)
  end

  # 给前端轮询用：背调跑完没有。
  def show
    render json: lead_json(@lead)
  end

  private

  # 动手之前先把这条领到自己名下。已经是自己的直接过；别人的／超上限返回提示文案。
  def ensure_mine
    return nil if @lead.holder_id == current_user.id

    result = Crm::LeadClaim.new(account: Current.account, user: current_user).call(@lead)
    result.ok ? nil : result.message
  end

  # 口径见 Crm::BaseController#visible_leads：跟所属拓客任务的可见性走，
  # 共享任务的线索全员能动——共享池本来就是给大家领的。
  def fetch_lead
    @lead = visible_leads.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Lead)
  end

  # 和 leads.json.jbuilder 是同一套字段：那边是列表，这边是单条操作后的回填。
  # 两边加字段要一起加，否则解锁/建档之后那一行会少东西。
  def lead_json(lead)
    {
      id: lead.id, status: lead.status, company_name: lead.company_name, domain: lead.domain,
      industry: lead.industry, country: lead.country, city: lead.city,
      person_name: lead.person_name, title: lead.title,
      email: lead.email, email_status: lead.email_status, linkedin_url: lead.linkedin_url,
      email_available: lead.email_available?, dup_customer_id: lead.dup_customer_id,
      crm_customer_id: lead.crm_customer_id
    }.merge(lead_signals(lead))
  end

  # 判断用的信号：搜索词、AI 初筛、背调、公司资料、行业黑名单。
  # 每个字段都写出来（哪怕是 nil）：这些值要覆盖前端那一行的旧值，
  # 少一个 key 就等于「保留原样」，解锁/丢弃之后那一行会显示过期数据。
  def lead_signals(lead)
    raw = lead.raw
    {
      matched_keyword: raw['matched_keyword'], apollo_tag: raw['apollo_tag'],
      market: raw['market'], screen: raw['screen'], screen_why: raw['screen_why'],
      screen_score: raw['screen_score'], bg: raw['bg'], org: raw['org'],
      site_url: Crm::SiteUrl.for(domain: lead.domain, website: raw.dig('org', 'website'),
                                 bg_url: raw.dig('bg', 'url')),
      discard_reason: raw['discard_reason'],
      # 背调排队中。前端据此显示「背调中…」并轮询。
      bg_running: raw['bg'].blank? && raw['bg_running_at'].present?,
      not_buyer: Crm::NaicsLabel.not_buyer?(lead.industry),
      mine: lead.holder_id == current_user.id, claimed_at: lead.claimed_at
    }
  end
end
