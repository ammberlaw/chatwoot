# == Schema Information
#
# Table name: mes_supplier_items
#
#  id              :bigint           not null, primary key
#  category        :string
#  color           :string           not null
#  material_code   :string           not null
#  name            :string           not null
#  specification   :string           not null
#  unit            :string           not null
#  unit_price      :decimal(14, 4)   not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  mes_material_id :bigint
#  supplier_id     :bigint           not null
#
# Indexes
#
#  index_mes_supplier_items_on_account_id                     (account_id)
#  index_mes_supplier_items_on_category                       (category)
#  index_mes_supplier_items_on_mes_material_id                (mes_material_id)
#  index_mes_supplier_items_on_supplier_id                    (supplier_id)
#  index_mes_supplier_items_on_supplier_id_and_material_code  (supplier_id,material_code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (supplier_id => mes_suppliers.id) ON DELETE => cascade
#
class Mes::SupplierItem < ApplicationRecord
  # SKU 编码分类（按仓别）：成品仓 / 半成品仓 / 原材料仓·主料 / 原材料仓·辅料 / 不良品仓
  CATEGORIES = %w[FINISHED SEMI RAW_MAIN RAW_AUX DEFECTIVE].freeze

  belongs_to :account
  belongs_to :supplier, class_name: 'Mes::Supplier', inverse_of: :supplier_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true

  before_validation :inherit_account, :normalize_code
  before_save :link_or_create_material

  validates :material_code, :name, :color, :specification, :unit, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :material_code, uniqueness: { scope: :supplier_id }
  validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 含税单价 = 未税单价 × (1 + 供应商税率%)；供应商未填税率时即未税价。
  def unit_price_taxed
    return unit_price if supplier&.tax_rate.blank?

    (unit_price * (1 + (supplier.tax_rate / 100))).round(4)
  end

  private

  def inherit_account
    self.account_id ||= supplier&.account_id
  end

  def normalize_code
    self.material_code = material_code.to_s.strip
  end

  # 物料编码与物料档案共享同一编码空间：已有编码直接挂档案；新编码自动建档（默认供应商=本供应商）。
  def link_or_create_material
    material = account.mes_materials.find_by(material_no: material_code)
    material ||= account.mes_materials.create!(
      material_no: material_code,
      name: name,
      specification: specification,
      unit: unit,
      category: category,
      product_line: supplier.product_line,
      default_supplier_id: supplier_id
    )
    self.mes_material = material
  end
end
