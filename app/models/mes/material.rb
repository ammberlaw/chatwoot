class Mes::Material < ApplicationRecord
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
