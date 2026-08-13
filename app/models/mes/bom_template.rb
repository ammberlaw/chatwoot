# 工程/PMC 复用的 BOM 模版：把常用成品的十几二十行用料存成模版，
# 建 BOM 时一键套用免得逐行重填。独立于 mes_boms 生命周期，不参与下发/挂用。
# == Schema Information
#
# Table name: mes_bom_templates
#
#  id                    :bigint           not null, primary key
#  base_qty              :decimal(14, 3)   default(1.0), not null
#  fg_inbound_days       :integer
#  material_inbound_days :integer
#  name                  :string           not null
#  picking_days          :integer
#  product_line          :string
#  production_days       :integer
#  purchasing_days       :integer
#  remark                :text
#  unit                  :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  owner_id              :bigint
#
# Indexes
#
#  index_mes_bom_templates_on_account_id    (account_id)
#  index_mes_bom_templates_on_owner_id      (owner_id)
#  index_mes_bom_templates_on_product_line  (product_line)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Mes::BomTemplate < ApplicationRecord
  include Mes::LineScoped

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  has_many :bom_template_items, class_name: 'Mes::BomTemplateItem', dependent: :destroy, inverse_of: :bom_template
  accepts_nested_attributes_for :bom_template_items, allow_destroy: true

  # 与 BOM 一致的各阶段预估天数（套用模版时一并带出）。
  LEAD_DAY_COLUMNS = %i[purchasing_days material_inbound_days picking_days production_days fg_inbound_days].freeze

  validates :name, presence: true
  validates :base_qty, numericality: { greater_than: 0 }

  private

  # 模版不挂成品，产线走控制器兜底（当前切换的产线）。
  def product_line_source = nil
end
