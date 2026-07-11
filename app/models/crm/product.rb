# 产品档案。对应 A-CRM(Twenty) 的 product（CRM_SPEC §2.1）。
# == Schema Information
#
# Table name: crm_products
#
#  id                :bigint           not null, primary key
#  category          :string
#  cost_price_micros :bigint
#  is_active         :boolean          default(TRUE), not null
#  name              :string           not null
#  pricing_currency  :string           default("USD")
#  remark            :text
#  sale_price_micros :bigint
#  sku               :string           not null
#  specification     :string
#  unit              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_crm_products_on_account_id          (account_id)
#  index_crm_products_on_account_id_and_sku  (account_id,sku) UNIQUE
#
class Crm::Product < ApplicationRecord
  CATEGORIES = %w[STANDARD CUSTOMIZED ACCESSORY OTHER].freeze

  belongs_to :account

  validates :name, presence: true
  validates :sku, presence: true, uniqueness: { scope: :account_id }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :pricing_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  scope :active, -> { where(is_active: true) }
end
