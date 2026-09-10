# 展会（用于展会邀约获客）：一场展会 → 一批客户邀约。
# 展会信息由业务员/管理员录入（展会名/城市/国家/日期/展位号/本次主打产品）。
# 匹配潜客按「国家/地区」口径从自己已有客户里筛（见 Crm::ExhibitionMatcher），
# 邀请函由 DeepSeek 生成、客户经带 token 的落地页在线确认到访。
# == Schema Information
#
# Table name: crm_exhibitions
#
#  id                :bigint           not null, primary key
#  booth_no          :string
#  city              :string
#  country           :string
#  ends_on           :date
#  featured_products :text
#  hall              :string
#  name              :string           not null
#  region            :string
#  starts_on         :date
#  status            :string           default("active"), not null
#  theme             :text
#  venue             :string
#  website           :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  account_owner_id  :bigint
#
# Indexes
#
#  index_crm_exhibitions_on_account_id             (account_id)
#  index_crm_exhibitions_on_account_id_and_status  (account_id,status)
#  index_crm_exhibitions_on_account_owner_id       (account_owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::Exhibition < ApplicationRecord
  belongs_to :account
  belongs_to :account_owner, class_name: 'User', optional: true

  has_many :invites, class_name: 'Crm::ExhibitionInvite', foreign_key: :crm_exhibition_id, dependent: :destroy, inverse_of: :exhibition

  STATUSES = %w[active closed].freeze

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  # 邀约进度统计：各阶段计数（用于看板/列表徽标）。
  def stage_counts
    invites.group(:stage).count
  end
end
