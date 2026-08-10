# TikTok 部门（团队式：负责人带成员）。店铺归属部门，数据按部门收口（见 Tiktok::AccessScope）。
# 成员经 account_users.tiktok_department_id 归属；负责人 leader_id 指向 users。
# == Schema Information
#
# Table name: tiktok_departments
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  leader_id  :bigint
#
# Indexes
#
#  idx_tiktok_departments_name            (account_id,name) UNIQUE
#  index_tiktok_departments_on_leader_id  (leader_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (leader_id => users.id) ON DELETE => nullify
#
class Tiktok::Department < ApplicationRecord
  belongs_to :account
  belongs_to :leader, class_name: 'User', optional: true
  has_many :account_users, foreign_key: :tiktok_department_id, dependent: :nullify, inverse_of: :tiktok_department
  has_many :members, through: :account_users, source: :user
  has_many :shops, class_name: 'Tiktok::Shop', foreign_key: :department_id, dependent: :nullify, inverse_of: :department

  validates :name, presence: true, uniqueness: { scope: :account_id }
end
