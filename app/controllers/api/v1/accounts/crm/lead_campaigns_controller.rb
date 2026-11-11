# 新客开发：主动拓客任务。
#
# 任务和线索都按负责人收口——拓客名单是业务员自己的工作面，
# 管理员/副管看全部（口径同 scope_by_owner）。
class Api::V1::Accounts::Crm::LeadCampaignsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_campaign, only: [:show, :update, :destroy, :build_profile, :search, :leads]
  helper_method :search_quota_for

  def index
    # 共享的任务全员可见（线索是共享池，谁挖的不重要，谁领的才重要）；
    # 没勾共享的只有负责人自己看得见。
    @campaigns = visible_campaigns.includes(:owner, :created_by).recent_first.limit(50)
    # 本月还能解锁几条。摆在页面上，业务员点之前就知道还剩多少，
    # 不至于点到一半被拦下来才发现额度没了。
    @quota = Crm::ApolloQuota.new(account: Current.account).status_for(current_user)
  end

  def show; end

  def create
    @campaign = Current.account.crm_lead_campaigns.new(campaign_params.merge(created_by: current_user))
    @campaign.owner_id = assigned_owner_id
    # 没自己写初筛条件就用公司级默认的——11 个人写 11 套标准，判出来的东西没有可比性。
    @campaign.screen_criteria = default_criteria if @campaign.screen_criteria.blank?
    @campaign.save!
    render :show
  end

  def update
    attrs = campaign_params
    attrs = attrs.merge(owner_id: assigned_owner_id) if params[:campaign].key?(:owner_id)
    @campaign.update!(attrs)
    render :show
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  # 生成理想客户画像 + 本地化关键词。不调 Apollo、不花 credits，
  # 料全来自我们自己的成交数据（见 Crm::LeadProfileBuilder）。
  def build_profile
    if Crm::LeadProfileBuilder.new(campaign: @campaign).call
      render :show, locals: { campaign: @campaign.reload }
    else
      render json: { error: @campaign.reload.last_error.presence || '画像生成失败，请重试' },
             status: :unprocessable_entity
    end
  end

  # 按画像生成的关键词去 Apollo 搜潜在客户。挖公司和探词表都不扣 credits
  #（2026-11-10 实测对账），真邮箱要人点「解锁」那一下才扣。
  #
  # ⚠️ **排队跑，不在请求里等**。一次搜索要三到五分钟（十几个关键词各翻几页，
  # 再整批送 AI 初筛），而请求 15 秒就被 Rack::Timeout 掐断——
  # 界面自己写着「通常需要三到五分钟」，却在 15 秒时弹 Internal Server Error，
  # 而且 status 已经改成 SEARCHING 没机会改回来，这个任务从此卡死
  #（2026-11-10 肖天海那个医疗一体机任务就是这么卡住的）。
  # 现在点完立刻返回，前端轮询 show 看 status 变成 DONE 没有。
  def search
    return render json: { error: '先生成客户画像' }, status: :unprocessable_entity if @campaign.keywords.blank?
    return render json: { error: '这个任务正在搜索中，等它跑完再点' }, status: :unprocessable_entity if @campaign.status == 'SEARCHING'

    # 挖客户的额度（2026-11-10 起）。挖公司是主要成本，不是只有解锁花钱——
    # 两个业务员各建了选 11~13 个国家的任务，一下午烧掉 400 多 credits，
    # 而他们并不知道点这个按钮要花钱。额度按任务负责人算。
    quota = Crm::ApolloQuota.new(account: Current.account).search_status_for(@campaign.owner)
    return render json: { error: search_quota_message(quota) }, status: :unprocessable_entity unless quota.allowed?

    Crm::LeadSearchJob.perform_later(@campaign.id)
    render json: { queued: true, status: 'SEARCHING' }
  end

  # 获客效果:搜索词 → 线索 → 建档 → 成交额。
  # 默认看全部任务的累计(效果是跨任务攒出来的),带 campaign_id 就只看那一个。
  def outcomes
    # 和列表、线索走同一个口径（visible_lead_campaigns）。
    # 原来这里单独写 scope_by_owner：业务员看得见共享任务的线索、领得走、建得了档，
    # 回头看「我挖的这些带来了什么」却是一片空白——和 2026-11-09 那个 404 同一个根子，
    # 可见范围在两处各写一遍，迟早一处放行另一处没放行。
    campaigns = visible_lead_campaigns
    campaigns = campaigns.where(id: params[:campaign_id]) if params[:campaign_id].present?
    stats = Crm::LeadOutcomeStats.new(campaigns: campaigns)
    memory = Crm::LeadScreenMemory.new(account: Current.account)
    render json: { summary: stats.summary, rows: stats.by_keyword.first(50),
                   learned: memory.examples, directions: memory.learned_directions }
  end

  # 线索池的排序。
  #
  # ① 匹配度分（没打分的按结论折算，否则老数据全沉底）
  # ② **有没有联系人**——2026-11-08 实测：判 yes 的 399 家里有 111 家（28%）
  #    一个联系人都没搜到，挖出来也打不着。以前它们按分数照样排在第一页，
  #    业务员一条条点进去才发现没人可联系。
  # ③ 已经是我们客户的沉到后面
  ORDER_SQL = "COALESCE((raw->>'screen_score')::int, " \
              "CASE raw->>'screen' WHEN 'yes' THEN 75 WHEN 'unsure' THEN 45 " \
              "WHEN 'no' THEN 10 ELSE 30 END) DESC, " \
              'person_name IS NULL, dup_customer_id IS NOT NULL, id'.freeze

  def leads
    # RELEASED 的不显示：保护期内没动静、已经被别人重新挖走了，
    # 还摆在原主列表里只会让两个人同时在跟同一家。
    scope = @campaign.leads.where.not(status: 'RELEASED')
    scope = scope.unclaimed if params[:filter] == 'open'
    # 排序：AI 判「像买家」的排最前，已经是我们客户的沉到后面。
    # 业务员最多看前几十条，顺序就是这个功能有没有用的分水岭。
    # 按**匹配度分**排，不按 yes/unsure/no 分档。
    # 分档排序的毛病是：条件措辞一改，yes 的条数就从 38 掉到 11（2026-11-08 实测差 3.5 倍），
    # 业务员看到的数量全看提示词怎么写。按分数排之后，第一页永远是最匹配的那批，
    # 多少条是业务员自己翻页决定的，和措辞无关。
    # 没打分的（老数据、模型漏给）按结论折算一个保守分，不至于全沉底。
    @leads = scope.order(Arel.sql(ORDER_SQL)).limit(300)
    # 「已是同事客户」现查，不只信搜索当时存的 dup_customer_id——
    # 客户常常是同事后来才建的，不现查那条线索就永远标不出来，而撞单恰恰发生在这种时候。
    # 同事领走的不显示——不是标出来，标出来等于让人盯着一份自己碰不得的名单。
    # 没人领的和自己领的都看得见（共享池）。
    # **经理和副管例外**：他们要查「谁领了什么、压了多久」，不给看就没法管。
    @leads = @leads.reject { |l| hide_from_me?(l) }
    @holders = holder_names(@leads)
    @dupes = Crm::LeadDuplicate.new(account: Current.account).find_many(@leads.map(&:domain))
    @held_count = Crm::LeadClaim.new(account: Current.account, user: current_user).held_count
    render :leads
  end

  # 管理端概览：这条线上每个人在干什么。
  # 业务员看不到别人的数——这是管理视图，不是排行榜。
  def team_stats
    return render json: { error: '只有经理和管理员能看' }, status: :forbidden unless manager?

    stats = Crm::LeadTeamStats.new(account: Current.account, owner_ids: crm_visible_owner_ids)
    render json: { summary: stats.summary, rows: stats.rows,
                   stale_days: Crm::LeadTeamStats::STALE_DAYS,
                   hold_days: Crm::Lead::HOLD_DAYS, hold_limit: Crm::Lead::HOLD_LIMIT }
  end

  # 共享线索池：**跨任务**的待领线索。
  #
  # 为什么必须单独有这个入口：池子是按「谁领谁得」设计的，但界面一直按任务组织——
  # 业务员想领一条，得一个任务一个任务翻（用户 2026-11-08 问「那池子在哪里」才发现）。
  # scope=pool 还没人领的（默认）；scope=mine 我领的。
  def pool
    scope = params[:scope].to_s == 'mine' ? my_leads : pool_leads
    @leads = top_leads_by_company(scope)
    @dupes = Crm::LeadDuplicate.new(account: Current.account).find_many(@leads.map(&:domain))
    @held_count = Crm::LeadClaim.new(account: Current.account, user: current_user).held_count
    @holders = {}
    render :leads
  end

  # 全公司已验证的搜索词，按市场分组。建任务时直接挑，不用从零写。
  def keyword_library
    render json: {
      markets: Crm::LeadKeywordLibrary.new(account: Current.account).by_market,
      default_criteria: Crm::AiSetting.for_account(Current.account).lead_default_criteria
    }
  end

  private

  # 搜索按计划负责人核算；解锁仍按操作者核算，两种额度不能混用。
  def search_quota_for(campaign)
    return if campaign.owner.nil?

    @search_quotas ||= {}
    @search_quota_service ||= Crm::ApolloQuota.new(account: Current.account)
    quota = @search_quotas[campaign.owner_id] ||= @search_quota_service.search_status_for(campaign.owner)
    { owner_id: campaign.owner_id, owner_name: campaign.owner.crm_display_name,
      used: quota.user_used, limit: quota.user_limit, remaining: quota.user_left, allowed: quota.allowed? }
  end

  # 拦下来要说清是谁的额度、用了多少、什么时候清零——只说「不让搜」会让人以为系统坏了。
  def search_quota_message(quota)
    "#{@campaign.owner&.crm_display_name || '这个任务的负责人'}本月挖客户的额度已用完" \
      "（#{quota.user_used}/#{quota.user_limit} 家）。下个月 1 号自动清零，" \
      '急用让管理员在「AI 设置」里单独调高。'
  end

  # 取前 N **家公司**的全部线索，而不是前 N 条线索。
  #
  # 前端是按公司折叠显示的（一家公司一行，底下挂它的几个联系人），
  # 而这里按条数截断——3896 条线索只对应 3048 家公司，848 条是同一家公司的重复行，
  # 于是「前 300 条」折叠完可能只剩两百出头家，真正的新公司被挤在看不见的地方。
  POOL_COMPANY_LIMIT = 300

  def top_leads_by_company(scope)
    ordered = scope.order(Arel.sql(ORDER_SQL))
    names = ordered.limit(POOL_COMPANY_LIMIT * 3).pluck(:company_name).uniq.first(POOL_COMPANY_LIMIT)
    return [] if names.empty?

    ordered.where(company_name: names).to_a
  end

  # 池子里能领的：共享任务里没人领的 + 保护期已过的。
  # 不共享任务的线索只有负责人看得见，所以单独并进来。
  def pool_leads
    base = Current.account.crm_leads.in_pool
    own = Current.account.crm_leads.where(
      crm_lead_campaign_id: Current.account.crm_lead_campaigns.where(owner_id: current_user.id,
                                                                     shared: false).select(:id),
      status: %w[FOUND UNLOCKED], owner_id: nil
    )
    Current.account.crm_leads.where(id: base.select(:id)).or(
      Current.account.crm_leads.where(id: own.select(:id))
    )
  end

  # 我领的、还没处理完的。
  def my_leads
    Current.account.crm_leads.where(owner_id: current_user.id, status: %w[FOUND UNLOCKED])
           .where(claimed_at: Crm::Lead::HOLD_DAYS.days.ago..)
  end

  def manager?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin? || au.crm_manager?
  end

  # 别人领走的藏起来；自己能管到的人（经理看本部门）不藏。
  def hide_from_me?(lead)
    holder = lead.holder_id
    return false if holder.blank? || holder == current_user.id

    ids = crm_visible_owner_ids
    ids != :all && ids.exclude?(holder)
  end

  # 给经理看的：这条在谁手上。业务员看不到这个字段（他们本来就看不见别人的线索）。
  def holder_names(leads)
    ids = leads.filter_map(&:holder_id).uniq - [current_user.id]
    return {} if ids.empty?

    User.where(id: ids).index_by(&:id).transform_values(&:crm_display_name)
  end

  def fetch_campaign
    @campaign = visible_campaigns.find(params[:id])
  end

  # 口径在 Crm::BaseController#visible_lead_campaigns，线索的单条操作也用同一个，
  # 不另造一套——两套口径一走偏就等于开了后门，或者看得见点不动。
  def visible_campaigns = visible_lead_campaigns

  def check_authorization
    authorize(Crm::LeadCampaign)
  end

  def campaign_params
    params.require(:campaign).permit(:name, :product_hint, :seed_keywords, :target_count,
                                     :screen_criteria, :default_customer_group, :auto_run, :shared,
                                     target_markets: [])
  end

  # 任务派给谁。经理建好任务直接指给业务员，业务员只看指给自己的那份
  # （用户 2026-11-08 定的分配方式：经理建、经理派）。
  #
  # ⚠️ owner_id **不在 permit 列表里**，必须走这里：能指派的只有管理员和经理，
  # 否则业务员改一下请求体就能把别人的任务抢过来。
  def assigned_owner_id
    wanted = params.dig(:campaign, :owner_id).presence
    return current_user.id if wanted.blank? || !can_assign?

    Current.account.account_users.exists?(user_id: wanted) ? wanted.to_i : current_user.id
  end

  def default_criteria
    Crm::AiSetting.for_account(Current.account).lead_default_criteria.presence
  end

  def can_assign?
    au = Current.account_user
    au.administrator? || au.crm_manager? || au.crm_role == 'deputy_admin'
  end
end
