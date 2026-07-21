# == Schema Information
#
# Table name: mes_materials
#
#  id                  :bigint           not null, primary key
#  category            :string
#  cost_price_micros   :bigint
#  currency            :string           default("CNY")
#  is_active           :boolean          default(TRUE), not null
#  material_no         :string           not null
#  name                :string           not null
#  product_line        :string
#  remark              :text
#  safety_stock        :decimal(14, 3)
#  specification       :string
#  unit                :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  default_supplier_id :bigint
#
# Indexes
#
#  index_mes_materials_on_account_and_product_line    (account_id,product_line)
#  index_mes_materials_on_account_id                  (account_id)
#  index_mes_materials_on_account_id_and_material_no  (account_id,material_no) UNIQUE
#  index_mes_materials_on_default_supplier_id         (default_supplier_id)
#
# Foreign Keys
#
#  fk_rails_...  (default_supplier_id => mes_suppliers.id) ON DELETE => nullify
#
class Mes::Material < ApplicationRecord
  include Mes::LineScoped

  CATEGORIES = %w[RAW SEMI CONSUMABLE].freeze
  CURRENCIES = %w[CNY USD EUR].freeze

  belongs_to :account
  belongs_to :default_supplier, class_name: 'Mes::Supplier', optional: true

  before_validation :assign_material_no, on: :create

  validates :name, presence: true
  validates :unit, presence: true
  validates :material_no, presence: true, uniqueness: { scope: :account_id }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :currency, inclusion: { in: CURRENCIES }, allow_blank: true

  scope :active, -> { where(is_active: true) }

  private

  def assign_material_no
    return if material_no.present?

    last = self.class.where(account_id: account_id)
               .where("material_no ~ '^MAT[0-9]+$'")
               .pick(Arel.sql("MAX(SUBSTRING(material_no FROM 4)::int)")) || 0
    self.material_no = format('MAT%05d', last + 1)
  end
end
