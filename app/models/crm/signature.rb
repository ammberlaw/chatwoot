# 个人手写签名（HR·KPI 电子签）：每个成员在本账号内存一张可复用的签名图，
# 考核表填报/打分/人事/总经理各环节「一键盖章」时取用。account_id + user_id 唯一。
# == Schema Information
#
# Table name: crm_signatures
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_crm_signatures_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class Crm::Signature < ApplicationRecord
  belongs_to :account
  belongs_to :user

  has_one_attached :image

  validates :user_id, uniqueness: { scope: :account_id }
end
