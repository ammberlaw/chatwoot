# 生产报工（阶段 6，按数量批量报工 · 车间 PC 录入）。
class Mes::ProductionRecord < ApplicationRecord
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

  def stamp_recorded_at
    self.recorded_at ||= Time.current
  end

  # 报工累加已产数量并推进阶段（首次报工 PICKING → PRODUCTION）。
  def apply_to_production_order
    production_order.add_produced!(qty_completed)
  end
end
