# == Schema Information
#
# Table name: mes_bom_items
#
#  id              :bigint           not null, primary key
#  amount_micros   :bigint
#  material_name   :string
#  material_no     :string
#  qty             :decimal(14, 3)   not null
#  rate_micros     :bigint
#  remark          :text
#  specification   :string
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

  before_validation :inherit_account

  # 照纸质生产任务单直接填：物料名称/用量必填，规格/编码/单位/备注选填。
  validates :material_name, presence: true
  validates :qty, presence: true, numericality: { greater_than: 0 }

  private

  # 嵌套创建时从父 BOM 继承租户。
  def inherit_account
    self.account_id ||= bom&.account_id
  end
end
