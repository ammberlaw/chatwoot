class Mes::Supplier < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  has_many :materials, class_name: 'Mes::Material', foreign_key: :default_supplier_id, dependent: :nullify, inverse_of: :default_supplier

  before_validation :assign_supplier_no, on: :create

  validates :name, presence: true
  validates :supplier_no, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(is_active: true) }

  private

  def assign_supplier_no
    return if supplier_no.present?

    last = self.class.where(account_id: account_id)
               .where("supplier_no ~ '^SUP[0-9]+$'")
               .pick(Arel.sql("MAX(SUBSTRING(supplier_no FROM 4)::int)")) || 0
    self.supplier_no = format('SUP%04d', last + 1)
  end
end
