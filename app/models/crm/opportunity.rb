# 销售商机。对应 A-CRM(Twenty) 的 opportunity（标准对象+9 个扩展字段，CRM_SPEC §3.3/§5）。
# sales_stage 是「商机漏斗看板」的分列依据；WON/LOST 为终态，「商机推进」视图排除两者。
# == Schema Information
#
# Table name: crm_opportunities
#
#  id                  :bigint           not null, primary key
#  amount_micros       :bigint
#  competitor          :string
#  currency            :string           default("CNY")
#  current_need        :text
#  expected_close_date :datetime
#  important           :boolean          default(FALSE), not null
#  is_in_public_pool   :boolean          default(FALSE), not null
#  last_activity_at    :datetime
#  loss_reason         :string
#  name                :string           not null
#  next_action         :string
#  opportunity_remark  :text
#  probability         :integer
#  public_pool_at      :datetime
#  sales_stage         :string           default("NEEDS_CONFIRMED"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_customer_id     :bigint
#  owner_id            :bigint
#
# Indexes
#
#  index_crm_opportunities_on_account_id                        (account_id)
#  index_crm_opportunities_on_account_id_and_is_in_public_pool  (account_id,is_in_public_pool)
#  index_crm_opportunities_on_account_id_and_sales_stage        (account_id,sales_stage)
#  index_crm_opportunities_on_crm_customer_id                   (crm_customer_id)
#  index_crm_opportunities_on_owner_id                          (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::Opportunity < ApplicationRecord
  # 4 阶段：需求确认(已报价) / 样品中 / 已成交 / 输单
  SALES_STAGES = %w[NEEDS_CONFIRMED SAMPLING WON LOST].freeze
  LOSS_REASONS = %w[PRICE DELIVERY QUALITY COMPETITOR CANCELLED NEED_CHANGED].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :owner, class_name: 'User', optional: true

  validates :name, presence: true
  validates :sales_stage, inclusion: { in: SALES_STAGES }
  validates :loss_reason, inclusion: { in: LOSS_REASONS }, allow_blank: true
  validates :probability, numericality: { in: 0..100 }, allow_nil: true
  validates :currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  scope :open_stages, -> { where.not(sales_stage: %w[WON LOST]) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  scope :in_public_pool, -> { where(is_in_public_pool: true) }
  scope :in_private_pool, -> { where(is_in_public_pool: false) }

  def amount
    amount_micros.to_f / 1_000_000 if amount_micros
  end

  # 释放到商机公海：脱离原负责人，全员可见可认领（与客户公海同构）。
  def move_to_public_pool!(at: Time.current)
    update!(is_in_public_pool: true, public_pool_at: at, owner_id: nil)
  end
end
