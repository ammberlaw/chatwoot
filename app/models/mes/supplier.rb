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
  include Mes::LineScoped
  # 供应商的「事业部」就是产线，建档时必填。
  # 不是洁癖：供应物料里只要有一个没见过的编码，保存时会顺带给它在**物料档案**建一条
  # （见 Mes::SupplierItem#link_or_create_material），而物料档案是主数据、产线必填。
  # 事业部留空 → 档案建不出来 → 整张供应商单回滚，而且报错信息会丢在嵌套保存里
  # （生产 2026-10-10 实际发生：前端只弹一个裸 AxiosError 422，三次都存不上）。
  # 生产现有 327 个供应商、2787 条物料档案产线全都有值，「未指定」从来没存成功过。
  require_product_line!

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
