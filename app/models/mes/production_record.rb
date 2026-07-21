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

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder'
  belongs_to :operator, class_name: 'User', optional: true

  before_validation :inherit_account
  before_validation :stamp_recorded_at, on: :create
  after_create :apply_to_production_order

  validates :qty_completed, numericality: { greater_than_or_equal_to: 0 }
  validates :qty_returned, :qty_scrap, numericality: { greater_than_or_equal_to: 0 }

  private

  def inherit_account
    self.account_id ||= production_order&.account_id
  end

  def product_line_source = production_order

  def stamp_recorded_at
    self.recorded_at ||= Time.current
  end

  # 报工累加已产数量并推进阶段（首次报工 PICKING → PRODUCTION）。
  def apply_to_production_order
    production_order.add_produced!(qty_completed)
  end
end
