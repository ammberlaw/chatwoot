# == Schema Information
#
# Table name: mes_board_owners
#
#  id           :bigint           not null, primary key
#  board_key    :string           not null
#  manager_ids  :bigint           default([]), not null, is an Array
#  product_line :string           default(""), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_mes_board_owners_on_account_board_line  (account_id,board_key,product_line) UNIQUE
#  index_mes_board_owners_on_account_id          (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Mes::BoardOwner < ApplicationRecord
  belongs_to :account

  # 同一阶段每条产品线各一份负责人（product_line '' = 全部产线/通用回落）。
  validates :board_key, presence: true, uniqueness: { scope: [:account_id, :product_line] }

  # 板块负责人（可多人）：页面直接展示，业务据此知道该阶段找谁。
  def managers
    User.where(id: manager_ids)
  end
end
