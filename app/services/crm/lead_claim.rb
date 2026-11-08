# 业务员从共享池里「领」一条线索。
#
# 线索池是全公司共享的：任何人建的任务，挖回来的公司都进同一个池子，谁都看得见。
# 领了才归你——保护期内（Crm::Lead::HOLD_DAYS）别人看不见也领不走，过期自动回池。
#
# 为什么不按任务分：任务是「怎么挖」，不是「归谁」。按任务分的话，
# 挖得勤的人占满池子，而他未必跟得过来——客户就烂在他手上。
class Crm::LeadClaim
  Result = Struct.new(:ok, :message, :lead, keyword_init: true)

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # 整家公司一起领：同一家公司名下的几个联系人分给两个人跟，等于内部撞单。
  def call(lead)
    return Result.new(ok: false, message: '这条线索属于不共享的任务，只有负责人能跟。') unless reachable?(lead)

    holder = lead.holder_id
    return Result.new(ok: false, message: taken_text(holder)) if holder.present? && holder != @user.id
    return Result.new(ok: true, message: '这条已经在你手上了', lead: lead) if holder == @user.id
    return Result.new(ok: false, message: over_limit_text) if over_limit?

    stamp(lead)
    Result.new(ok: true, message: "已领取 #{lead.company_name}，#{Crm::Lead::HOLD_DAYS} 天内归你跟进", lead: lead.reload)
  end

  # 手上压着多少条没处理完的（领了还没建档/丢弃的）。
  def held_count
    @account.crm_leads.where(owner_id: @user.id, status: %w[FOUND UNLOCKED])
            .where(claimed_at: Crm::Lead::HOLD_DAYS.days.ago..)
            .distinct.count(:company_name)
  end

  private

  # 共享任务里的谁都能领；不共享的只有任务负责人能领。
  def reachable?(lead)
    camp = lead.campaign
    camp.shared? || camp.owner_id == @user.id
  end

  def over_limit? = held_count >= Crm::Lead::HOLD_LIMIT

  def stamp(lead)
    reachable_ids = @account.crm_lead_campaigns.where(shared: true)
                            .or(@account.crm_lead_campaigns.where(owner_id: @user.id)).select(:id)
    scope = @account.crm_leads.where(company_name: lead.company_name, status: %w[FOUND UNLOCKED],
                                     crm_lead_campaign_id: reachable_ids)
    scope = scope.where(owner_id: nil).or(scope.where(claimed_at: ...Crm::Lead::HOLD_DAYS.days.ago))
    scope.update_all(owner_id: @user.id, claimed_at: Time.current, # rubocop:disable Rails/SkipsModelValidations
                     updated_at: Time.current)
  end

  def taken_text(holder_id)
    name = User.find_by(id: holder_id)&.crm_display_name || '同事'
    "这条已经被 #{name} 领走了，#{Crm::Lead::HOLD_DAYS} 天内跟不了。"
  end

  def over_limit_text
    "你手上已经压着 #{held_count} 条没处理完的（上限 #{Crm::Lead::HOLD_LIMIT} 条）。" \
      '先把手上的建档或丢弃掉，再来领新的。'
  end
end
