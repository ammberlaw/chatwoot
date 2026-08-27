# == Schema Information
#
# Table name: mes_suppliers
#
#  id            :bigint           not null, primary key
#  address       :text
#  bank_account  :string
#  bank_address  :string
#  bank_name     :string
#  bill_entity   :string           default("wintouch"), not null
#  category      :string
#  contact_name  :string
#  department    :string
#  email         :string
#  invoice_title :string
#  is_active     :boolean          default(TRUE), not null
#  name          :string           not null
#  phone         :string
#  product_line  :string
#  remark        :text
#  supplier_no   :string           not null
#  tax_no        :string
#  tax_rate      :decimal(5, 2)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  owner_id      :bigint
#
# Indexes
#
#  index_mes_suppliers_on_account_id                  (account_id)
#  index_mes_suppliers_on_account_id_and_supplier_no  (account_id,supplier_no) UNIQUE
#  index_mes_suppliers_on_owner_id                    (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Mes::Supplier < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  has_many :materials, class_name: 'Mes::Material', foreign_key: :default_supplier_id, dependent: :nullify, inverse_of: :default_supplier
  has_many :supplier_items, class_name: 'Mes::SupplierItem', dependent: :destroy, inverse_of: :supplier

  accepts_nested_attributes_for :supplier_items, allow_destroy: true

  before_validation :assign_supplier_no, on: :create

  # 开票主体/税模式：决定按供应商拆单导出套哪个采购单模板（wintouch=未税 / liontek=含税×1.13）。
  BILL_ENTITIES = %w[wintouch liontek].freeze

  validates :name, presence: true
  validates :supplier_no, presence: true, uniqueness: { scope: :account_id }
  validates :bill_entity, inclusion: { in: BILL_ENTITIES }

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
