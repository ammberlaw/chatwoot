# 明细文字 → 产品档案 的记忆。业务员选过一次，下次同样文字自动带出。
#
# 为什么需要：产品档案里 560 个名字重复（「863主板」42 条同名），靠名字匹配
# 永远命中多条；PI 上又多是英文自由描述，跟档案名对不上。这两类只能人选一次，
# 但不该让人选第二次——近 180 天 325 行明细只有 207 种文字、51% 是重复的。
# == Schema Information
#
# Table name: crm_product_aliases
#
#  id              :bigint           not null, primary key
#  hits            :integer          default(1), not null
#  last_used_at    :datetime
#  normalized_text :string           not null
#  sample_text     :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_product_id  :bigint           not null
#
# Indexes
#
#  idx_crm_product_aliases_unique               (account_id,normalized_text) UNIQUE
#  index_crm_product_aliases_on_crm_product_id  (crm_product_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => cascade
#
class Crm::ProductAlias < ApplicationRecord
  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product'

  validates :normalized_text, presence: true, uniqueness: { scope: :account_id }

  # 归一化：去掉所有空白 + 转小写。原文的大小写/空格差异不该影响命中
  #（实测明细里「 WT430ZD-C」带前导空格、「Q75x」大小写混用）。
  def self.normalize(text)
    text.to_s.gsub(/\s+/, '').downcase
  end

  # 记住一次选择。同一段文字改选别的产品时以最后一次为准（人更正了就该听人的）。
  def self.remember!(account:, text:, product_id:)
    key = normalize(text)
    return if key.blank? || product_id.blank?

    row = find_or_initialize_by(account_id: account.id, normalized_text: key)
    row.crm_product_id = product_id
    row.sample_text = text.to_s.strip.first(120)
    row.hits = row.persisted? ? row.hits + 1 : 1
    row.last_used_at = Time.current
    row.save!
  rescue ActiveRecord::RecordNotUnique
    # 并发下两条一起插——重试一次即可，命中同一行。
    retry
  end

  # 批量查：一次把多行明细的记忆取回来，避免逐行查库。
  def self.lookup(account:, texts:)
    keys = Array(texts).map { |t| normalize(t) }.reject(&:blank?).uniq
    return {} if keys.empty?

    where(account_id: account.id, normalized_text: keys).pluck(:normalized_text, :crm_product_id).to_h
  end
end
