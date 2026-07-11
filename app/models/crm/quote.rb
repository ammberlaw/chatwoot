# 报价单主体。对应 A-CRM(Twenty) 的 quote（CRM_SPEC §2.2/§5）。
# 状态机：DRAFT→SENT→CONFIRMED（确认后转销售订单）；EXPIRED/REJECTED 为失败态。
# == Schema Information
#
# Table name: crm_quotes
#
#  id                     :bigint           not null, primary key
#  discount_amount_micros :bigint
#  exchange_rate          :decimal(12, 6)
#  name                   :string           not null
#  quote_currency         :string           default("USD")
#  quote_date             :datetime
#  quote_no               :string           not null
#  remark                 :text
#  shipping_fee_micros    :bigint
#  status                 :string           default("DRAFT"), not null
#  subtotal_micros        :bigint
#  tax_amount_micros      :bigint
#  total_amount_micros    :bigint
#  valid_until            :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  contact_id             :bigint
#  crm_customer_id        :bigint
#  crm_opportunity_id     :bigint
#  owner_id               :bigint
#
# Indexes
#
#  index_crm_quotes_on_account_id               (account_id)
#  index_crm_quotes_on_account_id_and_quote_no  (account_id,quote_no) UNIQUE
#  index_crm_quotes_on_account_id_and_status    (account_id,status)
#  index_crm_quotes_on_contact_id               (contact_id)
#  index_crm_quotes_on_crm_customer_id          (crm_customer_id)
#  index_crm_quotes_on_crm_opportunity_id       (crm_opportunity_id)
#  index_crm_quotes_on_owner_id                 (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_opportunity_id => crm_opportunities.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::Quote < ApplicationRecord
  STATUSES = %w[DRAFT SENT CONFIRMED EXPIRED REJECTED].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  # 唯一的级联关系：删报价即删明细（CRM_SPEC §4）
  has_many :line_items, class_name: 'Crm::QuoteLineItem', foreign_key: :crm_quote_id, dependent: :destroy, inverse_of: :quote
  has_many :sales_orders, class_name: 'Crm::SalesOrder', foreign_key: :crm_quote_id, dependent: :nullify, inverse_of: :quote

  before_validation :generate_quote_no, on: :create

  validates :name, presence: true
  validates :quote_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :quote_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  scope :pending, -> { where(status: %w[DRAFT SENT]) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  private

  # 报价单号自动生成：QT-YYYYMMDD-NN（当天最大序号+1，删单不回填）。显式传入则尊重。
  def generate_quote_no
    return if quote_no.present?

    prefix = "QT-#{Time.zone.today.strftime('%Y%m%d')}"
    last_seq = account.crm_quotes
                      .where('quote_no LIKE ?', "#{prefix}-%")
                      .pick(Arel.sql("MAX(SPLIT_PART(quote_no, '-', 3)::int)")) || 0
    self.quote_no = format('%<prefix>s-%<seq>02d', prefix: prefix, seq: last_seq + 1)
  end
end
