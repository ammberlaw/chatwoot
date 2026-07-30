# 单据退回记录（横切）：任何操作单据（采购/入库/领料/报工…）被下游退回上一环节时记一条。
# 未解决(resolved_at 为空)的退回 = 该单据「当前处于退回中」；上游处理后 resolve，保留历史留痕。
# 与生产订单阶段级「拒收打回」(reject_to_previous!) 相互独立：这是单据级、不回退订单阶段。
# == Schema Information
#
# Table name: mes_document_returns
#
#  id              :bigint           not null, primary key
#  from_board_key  :string
#  reason          :text             not null
#  resolved_at     :datetime
#  returnable_type :string           not null
#  to_board_key    :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  resolved_by_id  :bigint
#  returnable_id   :bigint           not null
#  returned_by_id  :bigint
#
# Indexes
#
#  index_mes_document_returns_on_account_id               (account_id)
#  index_mes_document_returns_on_returnable               (returnable_type,returnable_id)
#  index_mes_document_returns_on_returnable_and_resolved  (returnable_type,returnable_id,resolved_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Mes::DocumentReturn < ApplicationRecord
  belongs_to :account
  belongs_to :returnable, polymorphic: true
  belongs_to :returned_by, class_name: 'User', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  validates :reason, presence: true
  validates :to_board_key, presence: true

  # 未解决的退回（存在即表示单据处于退回状态）。
  scope :active, -> { where(resolved_at: nil) }
end
