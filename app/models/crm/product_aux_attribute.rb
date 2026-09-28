# 产品辅助属性（见迁移说明）：同一物料编码下的可选变体，开单时单选其一。
# == Schema Information
#
# Table name: crm_product_aux_attributes
#
#  id             :bigint           not null, primary key
#  code           :string           not null
#  is_active      :boolean          default(TRUE), not null
#  name           :string           not null
#  position       :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  crm_product_id :bigint           not null
#
# Indexes
#
#  idx_crm_aux_attrs_on_product   (crm_product_id)
#  idx_crm_aux_attrs_unique_code  (account_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => cascade
#
class Crm::ProductAuxAttribute < ApplicationRecord
  self.table_name = 'crm_product_aux_attributes'

  belongs_to :account
  belongs_to :product, class_name: 'Crm::Product', foreign_key: :crm_product_id, inverse_of: :aux_attributes

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { scope: :account_id }

  before_validation :assign_code, on: :create

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:position, :id) }

  private

  # 编码照金蝶口径自动生成：<物料编码>_001、_002…
  # 取现有最大序号 +1，删掉中间某个也不会撞号。
  def assign_code
    return if code.present?

    sku = product&.sku.presence || "P#{crm_product_id}"
    used = self.class.where(account_id: account_id, crm_product_id: crm_product_id)
                .pluck(:code)
                .filter_map { |c| c[/_(\d+)\z/, 1]&.to_i }
    self.code = format('%s_%03d', sku, (used.max || 0) + 1)
  end
end
