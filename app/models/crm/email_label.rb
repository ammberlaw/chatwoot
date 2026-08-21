# 邮件标签定义（每账户一套，如「待回复 / 重要 / 等付款」）。邮件侧用 crm_emails.label_ids
# 数组列引用本表 id（沿用仓库既有数组列惯例，不建 join 表）。
# == Schema Information
#
# Table name: crm_email_labels
#
#  id         :bigint           not null, primary key
#  color      :string           default("slate"), not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_crm_email_labels_on_account_id           (account_id)
#  index_crm_email_labels_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::EmailLabel < ApplicationRecord
  # 与前端胶囊配色（PILL）同色系可选值。
  COLORS = %w[slate iris blue teal amber ruby violet].freeze
  # 首次使用时种入的默认标签（外贸日常最常用的几类）。
  DEFAULTS = [
    { name: '待回复', color: 'amber' },
    { name: '重要', color: 'ruby' },
    { name: '等付款', color: 'teal' },
    { name: '重点客户', color: 'iris' }
  ].freeze

  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :color, inclusion: { in: COLORS }

  scope :ordered, -> { order(:position, :id) }

  # 账户还没有任何标签时，种入一组默认标签（幂等，进标签管理/邮件页时懒加载）。
  def self.seed_defaults!(account)
    return if exists?(account_id: account.id)

    DEFAULTS.each_with_index do |label, i|
      create!(account_id: account.id, name: label[:name], color: label[:color], position: i)
    end
  end
end
