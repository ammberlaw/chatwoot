# Apollo 标签词表的本地缓存：一个词全公司只探一次。
#
# 探词走 mixed_companies_count，和挖公司是同一个端点。原来只有进程内缓存，
# 每轮任务重探一遍——2026-11-10 台账里 406 次探词调用，大部分是重复的。
#
# 标签存不存在是全局事实，不随国家和任务变，所以可以安心落库。
# 词表本身会变（Apollo 偶尔增删标签），所以给个过期时间，过期了重探一次。
# == Schema Information
#
# Table name: crm_apollo_tags
#
#  id         :bigint           not null, primary key
#  phrase     :string           not null
#  probes     :integer          default(0), not null
#  tag        :string
#  total      :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_crm_apollo_tags_on_account_id_and_phrase  (account_id,phrase) UNIQUE
#
class Crm::ApolloTag < ApplicationRecord
  self.table_name = 'crm_apollo_tags'

  belongs_to :account

  # 多久重探一次。标签词表变动极慢，一个季度足够。
  TTL = 90.days

  # 命中返回 [tag, total]；没缓存过返回 nil（调用方去探）。
  # 注意 tag 为 nil 也是**有效结论**（「这个词词表里没有」），不能当成未命中。
  def self.lookup(account_id, phrase)
    row = find_by(account_id: account_id, phrase: phrase)
    return nil if row.nil? || row.updated_at < TTL.ago

    [row.tag, row.total]
  end

  def self.remember(account_id, phrase, tag, total)
    row = find_or_initialize_by(account_id: account_id, phrase: phrase)
    row.assign_attributes(tag: tag, total: total, probes: row.probes.to_i + 1)
    row.save!
    row
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
