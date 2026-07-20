# == Schema Information
#
# Table name: mes_bom_items
#
#  id              :bigint           not null, primary key
#  amount_micros   :bigint
#  qty             :decimal(14, 3)   not null
#  rate_micros     :bigint
#  remark          :text
#  unit            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  bom_id          :bigint           not null
#  mes_material_id :bigint
#
# Indexes
#
#  index_mes_bom_items_on_account_id       (account_id)
#  index_mes_bom_items_on_bom_id           (bom_id)
#  index_mes_bom_items_on_mes_material_id  (mes_material_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_id => mes_boms.id) ON DELETE => cascade
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#
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
