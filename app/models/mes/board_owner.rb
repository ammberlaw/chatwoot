# == Schema Information
#
# Table name: mes_board_owners
#
#  id          :bigint           not null, primary key
#  board_key   :string           not null
#  manager_ids :bigint           default([]), not null, is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_mes_board_owners_on_account_id                (account_id)
#  index_mes_board_owners_on_account_id_and_board_key  (account_id,board_key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Mes::BoardOwner < ApplicationRecord
  belongs_to :account

  validates :board_key, presence: true, uniqueness: { scope: :account_id }

  # 板块负责人（可多人）：页面直接展示，业务据此知道该阶段找谁。
  def managers
    User.where(id: manager_ids)
  end
end
