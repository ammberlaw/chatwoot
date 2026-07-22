# BOM 模版的用料明细行（结构同 mes_bom_items，供套用时复制）。
# == Schema Information
#
# Table name: mes_bom_template_items
#
#  id              :bigint           not null, primary key
#  material_name   :string
#  material_no     :string
#  qty             :decimal(14, 3)   not null
#  remark          :text
#  specification   :string
#  unit            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  bom_template_id :bigint           not null
#
# Indexes
#
#  index_mes_bom_template_items_on_account_id       (account_id)
#  index_mes_bom_template_items_on_bom_template_id  (bom_template_id)
#
# Foreign Keys
#
#  fk_rails_...  (bom_template_id => mes_bom_templates.id) ON DELETE => cascade
#
class Mes::BomTemplateItem < ApplicationRecord
  belongs_to :account
  belongs_to :bom_template, class_name: 'Mes::BomTemplate', inverse_of: :bom_template_items

  before_validation :inherit_account

  validates :material_name, presence: true
  validates :qty, presence: true, numericality: { greater_than: 0 }

  private

  # 嵌套创建时从父模版继承租户。
  def inherit_account
    self.account_id ||= bom_template&.account_id
  end
end
