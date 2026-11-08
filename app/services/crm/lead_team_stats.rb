# 管理端要的那张表：新客开发这条线上，每个人到底在干什么。
#
# 为什么必须有：线索改成「谁领谁得」之后，经理手上**一个数字都没有**——
# 看不到谁领了多少、谁压着不动、谁领了却不建档。
# 持有上限（Crm::Lead::HOLD_LIMIT）和 14 天自动回池只是兜底，
# 等回池了那两周已经浪费掉了，而且没人知道浪费在谁手上。
class Crm::LeadTeamStats
  # 领了超过这么多天还没动的，算「压着」——保护期一半，还来得及提醒。
  STALE_DAYS = 7

  # owner_ids: :all 或 user_id 数组（口径同 Crm::AccessScope#visible_owner_ids）
  def initialize(account:, owner_ids: :all, since: nil)
    @account = account
    @owner_ids = owner_ids
    @since = since || Time.current.beginning_of_month
  end

  # 每人一行，按「手上压着的」从多到少排——最该找谁谈话，一眼看得见。
  def rows
    ids = active_user_ids
    return [] if ids.empty?

    names = User.where(id: ids).index_by(&:id)
    ids.map { |id| row_for(id, names[id]) }.sort_by { |r| [-r[:stale], -r[:holding]] }
  end

  def summary
    all = rows
    { people: all.size, holding: all.sum { |r| r[:holding] }, stale: all.sum { |r| r[:stale] },
      claimed: all.sum { |r| r[:claimed] }, discarded: all.sum { |r| r[:discarded] },
      unlocked: all.sum { |r| r[:unlocked] } }
  end

  private

  def row_for(id, user)
    held = holding_scope.where(owner_id: id)
    { user_id: id, name: user&.crm_display_name || "用户 #{id}" }
      .merge(holding_bits(held)).merge(period_bits(id))
  end

  # 此刻手上的状况。
  def holding_bits(held)
    { holding: held.distinct.count(:company_name),
      stale: held.where(claimed_at: ...STALE_DAYS.days.ago).distinct.count(:company_name),
      oldest_days: oldest_days(held) }
  end

  # 这段时间里的产出。
  #
  # ⚠️ 每个数都按**它自己的事件时间**算，别混用：
  # 建档数一度是按「领取时间」筛的，结果上月领、本月建的档全被算丢了。
  # 建档时间取客户档案的建立时间（线索上没有单独的建档时间戳）。
  # convert = 建档 / 领取，这条线上最核心的指标。
  def period_bits(id)
    taken = scoped.where(owner_id: id, claimed_at: @since..).distinct.count(:company_name)
    claimed = scoped.where(status: 'CLAIMED', owner_id: id)
                    .joins(:crm_customer).where(crm_customers: { created_at: @since.. })
                    .distinct.count(:company_name)
    { taken: taken, claimed: claimed,
      discarded: scoped.where(discarded_by_id: id, discarded_at: @since..).distinct.count(:company_name),
      unlocked: scoped.where(unlocked_by_id: id, unlocked_at: @since..).count,
      convert: taken.zero? ? nil : (100.0 * claimed / taken).round }
  end

  # 手上压着、还没处理完的（保护期内）。
  def holding_scope
    scoped.where(status: %w[FOUND UNLOCKED]).where.not(owner_id: nil)
          .where(claimed_at: Crm::Lead::HOLD_DAYS.days.ago..)
  end

  def oldest_days(scope)
    at = scope.minimum(:claimed_at)
    at && ((Time.current - at) / 1.day).floor
  end

  def scoped
    base = @account.crm_leads
    @owner_ids == :all ? base : base.where(owner_id: @owner_ids).or(base.where(discarded_by_id: @owner_ids))
  end

  # 这段时间里有过动作的人：领过、建过档、丢过、解锁过。
  def active_user_ids
    cols = [:owner_id, :discarded_by_id, :unlocked_by_id]
    ids = cols.flat_map { |col| @account.crm_leads.where.not(col => nil).distinct.pluck(col) }.uniq
    @owner_ids == :all ? ids : ids & Array(@owner_ids)
  end
end
