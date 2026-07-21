# == Schema Information
#
# Table name: mes_boms
#
#  id                         :bigint           not null, primary key
#  base_qty                   :decimal(14, 3)   default(1.0), not null
#  bom_no                     :string           not null
#  estimated_lead_days        :integer
#  fg_inbound_days            :integer
#  is_active                  :boolean          default(TRUE), not null
#  is_default                 :boolean          default(FALSE), not null
#  material_inbound_days      :integer
#  picking_days               :integer
#  product_line               :string
#  production_days            :integer
#  purchasing_days            :integer
#  remark                     :text
#  total_material_cost_micros :bigint
#  unit                       :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  crm_product_id             :bigint
#  owner_id                   :bigint
#
# Indexes
#
#  index_mes_boms_on_account_and_product_line  (account_id,product_line)
#  index_mes_boms_on_account_id                (account_id)
#  index_mes_boms_on_account_id_and_bom_no     (account_id,bom_no) UNIQUE
#  index_mes_boms_on_crm_product_id            (crm_product_id)
#  index_mes_boms_on_owner_id                  (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Mes::Bom < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :bom_items, class_name: 'Mes::BomItem', dependent: :destroy, inverse_of: :bom
  accepts_nested_attributes_for :bom_items, allow_destroy: true

  # 按阶段预估天数（工程/PMC 分部门填），求和 = 预计生产周期（不含销售出库/物流）。
  LEAD_DAY_COLUMNS = %i[purchasing_days material_inbound_days picking_days production_days fg_inbound_days].freeze

  validates :bom_no, presence: true, uniqueness: { scope: :account_id }
  validates :base_qty, numericality: { greater_than: 0 }

  scope :active, -> { where(is_active: true) }

  def self.document_number_prefix = 'BOM'
  def self.document_number_column = :bom_no

  # 各阶段预估天数求和；无填写则回退旧的整体预估交期。
  def total_lead_days
    sum = LEAD_DAY_COLUMNS.sum { |col| public_send(col).to_i }
    sum.positive? ? sum : estimated_lead_days.to_i
  end

  private

  def product_line_source = crm_product
end
