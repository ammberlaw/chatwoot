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
#  product_line      :string
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
#  index_crm_products_on_account_and_product_line  (account_id,product_line)
#  index_crm_products_on_account_id                (account_id)
#  index_crm_products_on_account_id_and_sku        (account_id,sku) UNIQUE
#
class Crm::Product < ApplicationRecord
  CATEGORIES = %w[STANDARD CUSTOMIZED ACCESSORY OTHER].freeze
  # 产品线（页面分流维度）：平板电脑、商显设备、工控类（与 CRM 客户产品分组一致）。
  # 真值挂产品档案，MES 各单据由此带出。
  PRODUCT_LINES = %w[TABLET COMMERCIAL_DISPLAY INDUSTRIAL_CONTROL].freeze

  belongs_to :account

  validates :name, presence: true
  validates :sku, presence: true, uniqueness: { scope: :account_id }
  validates :category, inclusion: { in: CATEGORIES }, allow_blank: true
  validates :product_line, inclusion: { in: PRODUCT_LINES }, allow_blank: true
  validates :pricing_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  scope :active, -> { where(is_active: true) }
end
