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

  # 某人是不是「这条产线这个板块」的负责人。本线没单独配就回落通用配置（product_line ''）。
  #
  # 这张表本来只用来展示「该找谁」，但它记的恰恰就是各产线各环节归谁管，
  # 拿来当权限依据比按 MES 角色一刀切准得多：平板产线的生产领料负责人配的是杨义
  # （MES 角色「生产」），按角色判他开不了领料单，而「平板车间的领料单自己开」
  # 正是配置本来要表达的意思。配置在「设置阶段负责人」里就能改，不用动代码。
  def self.manager?(account, board_key, product_line, user_id)
    return false if user_id.blank?

    rows = account.mes_board_owners.where(board_key: board_key).to_a
    row = rows.find { |r| r.product_line.presence == product_line.presence } ||
          rows.find { |r| r.product_line.blank? }
    row&.manager_ids.to_a.include?(user_id)
  end
end
