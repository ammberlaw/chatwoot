# 生产报工（阶段 6，按数量批量报工 · 车间 PC 录入）。
# == Schema Information
#
# Table name: mes_production_records
#
#  id                  :bigint           not null, primary key
#  operation_name      :string
#  product_line        :string
#  qty_completed       :decimal(14, 3)   default(0.0), not null
#  qty_returned        :decimal(14, 3)   default(0.0), not null
#  qty_scrap           :decimal(14, 3)   default(0.0), not null
#  recorded_at         :datetime
#  remark              :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  operator_id         :bigint
#  production_order_id :bigint           not null
#
# Indexes
#
#  index_mes_production_records_on_account_and_product_line  (account_id,product_line)
#  index_mes_production_records_on_account_id                (account_id)
#  index_mes_production_records_on_operator_id               (operator_id)
#  index_mes_production_records_on_production_order_id       (production_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => cascade
#
class Mes::ProductionRecord < ApplicationRecord
  include Mes::LineScoped
  include Mes::Returnable

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder'
  belongs_to :operator, class_name: 'User', optional: true

  before_validation :inherit_account
  before_validation :stamp_recorded_at, on: :create
  after_create :apply_to_production_order

  validates :qty_completed, numericality: { greater_than_or_equal_to: 0 }
  validates :qty_returned, :qty_scrap, numericality: { greater_than_or_equal_to: 0 }

  # ── 单据退回（Mes::Returnable）──：退回目标 = 生产领料板块（料不对退回仓库/领料）。
  # 报工无过账态、无单号，恒可退，单号用 报工#id。
  def document_board_key = 'mes_production_records_index'
  def return_document_label = '生产报工单'
  def return_document_no = "报工##{id}"
  def returnable? = true

  private

  def inherit_account
    self.account_id ||= production_order&.account_id
  end

  def product_line_source = production_order

  def stamp_recorded_at
    self.recorded_at ||= Time.current
  end

  # 报工累加已产数量并推进阶段（首次报工 PICKING → PRODUCTION），
  # 有实际产出则通知仓库来做成品入库（全部/部分完工都推）。
  def apply_to_production_order
    production_order.add_produced!(qty_completed)
    production_order.notify_fg_inbound_ready(qty_completed, actor: operator) if qty_completed.to_d.positive?
  end
end
