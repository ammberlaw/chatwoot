# 商机超期自动进商机公海（与客户公海同机制，规则同在公海设置页配置）。
# 超过 opportunity_stale_days 天无任何更新（编辑/拖动推进都会刷新 updated_at）
# 的在管推进中商机批量释放：已成交/输单终态与已在公海的不参与。
class Crm::RecycleStaleOpportunitiesJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where(id: Crm::Opportunity.distinct.select(:account_id)).find_each do |account|
      recycle_for_account(account)
    end
  end

  private

  def recycle_for_account(account)
    settings = Crm::PublicPoolSetting.for_account(account)
    return unless settings.opportunity_recycle_enabled?

    cutoff = settings.opportunity_stale_days.days.ago
    stale = account.crm_opportunities.in_private_pool.open_stages
                   .where.not(owner_id: nil)
                   .where(updated_at: ..cutoff)
    # 批量释放，单条 UPDATE 无需逐条校验
    count = stale.update_all(is_in_public_pool: true, public_pool_at: Time.current, owner_id: nil) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info "[Crm::RecycleStaleOpportunitiesJob] account=#{account.id} recycled=#{count}"
  end
end
