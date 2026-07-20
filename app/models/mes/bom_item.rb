class Mes::BomItem < ApplicationRecord
  belongs_to :account
  belongs_to :bom, class_name: 'Mes::Bom', inverse_of: :bom_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true

  before_validation :inherit_account, :compute_amount
  after_save :sync_bom_total
  after_destroy :sync_bom_total

  validates :qty, presence: true, numericality: { greater_than: 0 }

  private

  # 嵌套创建时从父 BOM 继承租户。
  def inherit_account
    self.account_id ||= bom&.account_id
  end

  # 小计 = 用量 × 单价。
  def compute_amount
    self.amount_micros = ((qty || 0).to_d * (rate_micros || 0)).round
  end

  def sync_bom_total
    bom.recompute_total_cost!
  end
end
