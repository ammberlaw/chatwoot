# 一次 Apollo 调用的流水。
#
# 为什么要记：Apollo 按「导出的记录数」计费，而我们这边一直只在失败时写日志，
# 成功的调用什么都不留。于是后台看到「某天烧了 1084 credits」却查不出是哪个动作干的，
# 只能靠推——2026-11-09 就推错过一次，代价是整个计费周期的额度。
#
# 只记用量不记金额：单价随套餐变，折算成钱很快过期；返回条数是硬事实。
# == Schema Information
#
# Table name: crm_apollo_calls
#
#  id             :bigint           not null, primary key
#  duration_ms    :integer
#  endpoint       :string           not null
#  http_status    :integer
#  returned_count :integer          default(0), not null
#  scene          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_crm_apollo_calls_on_account_id_and_created_at            (account_id,created_at)
#  index_crm_apollo_calls_on_account_id_and_scene_and_created_at  (account_id,scene,created_at)
#
class Crm::ApolloCall < ApplicationRecord
  self.table_name = 'crm_apollo_calls'

  belongs_to :account
  belongs_to :user, optional: true

  # 记一笔。**绝不能让记账失败连累主流程**——这是旁路账本，不是业务。
  # attrs: endpoint, scene, returned_count, http_status, duration_ms, user
  def self.log(account:, endpoint:, scene:, **attrs)
    create!(account_id: account.id, user_id: attrs[:user]&.id, endpoint: endpoint, scene: scene,
            returned_count: attrs[:returned_count].to_i, http_status: attrs[:http_status],
            duration_ms: attrs[:duration_ms])
  rescue StandardError => e
    Rails.logger.warn("[Crm::ApolloCall] 记账失败 #{endpoint}/#{scene}: #{e.class} #{e.message}")
    nil
  end

  # 这个月按场景汇总：{ 场景 => { calls:, records: } }。
  # records 是对账的锚——拿它和 Apollo 后台的消耗比，就知道哪个动作在扣费。
  def self.month_summary(account, since: Time.current.beginning_of_month)
    where(account_id: account.id, created_at: since..)
      .group(:scene)
      .pluck(Arel.sql('scene, COUNT(*), COALESCE(SUM(returned_count), 0)'))
      .to_h { |scene, calls, records| [scene, { calls: calls, records: records }] }
  end
end
