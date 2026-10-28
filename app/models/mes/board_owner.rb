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
  # 这个板块该通知谁。**与 manager? 的口径有意不同**：manager? 判的是权限
  # （能不能动这张单），宁可窄；这里判的是通知（谁该来处理），宁可宽。
  #
  # · 配了本产线的 → 就这几个人
  # · 本产线没配 → 回落通用行（product_line ''）
  # · 单据本身没有产线、或本产线和通用行都没配人 → 所有产线的负责人都通知，谁先看到谁处理。
  #   漏发的代价是货压在仓库没人管，多发的代价只是一条通知。
  #
  # ⚠️ 各处原先直接 `find_by(board_key:)`，那是按 id 取**任意一行**，产线根本不看。
  # 2026-10-29 核实：成品入库板块两条产线都配了人（商显=吴明、平板=贺聪），
  # 但 find_by 永远只拿到 id 小的那条，所以 38 条「成品入库待清点」全发给了吴明——
  # 其中 37 条本来就该归他（商显），**错的是那 1 条平板的，贺聪一条没收到**。
  # 出库板块更糟：只配了商显一行，平板那张现货出库单还挂在草稿没提交，
  # 一旦提交就必然发错人。错的量不大是因为平板的单还少，不是因为逻辑没问题。
  def self.notify_ids(account, board_key, product_line)
    rows = account.mes_board_owners.where(board_key: board_key).to_a
    everyone = rows.flat_map(&:manager_ids).uniq
    return everyone if product_line.blank?

    # 本产线没配、通用行也没配：宁可全体都收到，也别让这张单谁都看不见。
    # 出库板块生产上就只配了商显一行，平板的单按产线找是一个人都找不出来的。
    row_for(rows, product_line)&.manager_ids.presence || everyone
  end

  # 本产线那一行，没有就回落通用行（product_line ''）。
  def self.row_for(rows, product_line)
    rows.find { |r| r.product_line.presence == product_line.presence } ||
      rows.find { |r| r.product_line.blank? }
  end
  private_class_method :row_for

  def self.manager?(account, board_key, product_line, user_id)
    return false if user_id.blank?

    rows = account.mes_board_owners.where(board_key: board_key).to_a
    row = rows.find { |r| r.product_line.presence == product_line.presence } ||
          rows.find { |r| r.product_line.blank? }
    row&.manager_ids.to_a.include?(user_id)
  end
end
