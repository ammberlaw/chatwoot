# 销售订单。对应 A-CRM(Twenty) 的 salesOrder（CRM_SPEC §2.4/§5/§12.7）。
# 增改删订单会回写所属客户的成交汇总（对应 Twenty 的 customer-deal-rollup 触发器）。
# == Schema Information
#
# Table name: crm_sales_orders
#
#  id                   :bigint           not null, primary key
#  cost_amount_micros   :bigint
#  delivery_date        :datetime
#  exchange_rate        :decimal(12, 6)
#  name                 :string           not null
#  order_amount_micros  :bigint
#  order_currency       :string           default("CNY")
#  order_date           :datetime         not null
#  order_no             :string           not null
#  profit_amount_micros :bigint
#  profit_rate          :decimal(6, 2)
#  remark               :text
#  status               :string           default("PENDING_CONFIRMATION"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint
#  crm_customer_id      :bigint
#  crm_opportunity_id   :bigint
#  owner_id             :bigint
#
# Indexes
#
#  index_crm_sales_orders_on_account_id                 (account_id)
#  index_crm_sales_orders_on_account_id_and_order_date  (account_id,order_date)
#  index_crm_sales_orders_on_account_id_and_order_no    (account_id,order_no) UNIQUE
#  index_crm_sales_orders_on_account_id_and_status      (account_id,status)
#  index_crm_sales_orders_on_contact_id                 (contact_id)
#  index_crm_sales_orders_on_crm_customer_id            (crm_customer_id)
#  index_crm_sales_orders_on_crm_opportunity_id         (crm_opportunity_id)
#  index_crm_sales_orders_on_owner_id                   (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_opportunity_id => crm_opportunities.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::SalesOrder < ApplicationRecord
  STATUSES = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT SHIPPED COMPLETED CANCELLED].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :owner, class_name: 'User', optional: true

  before_validation :generate_order_no, on: :create

  validates :name, presence: true
  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :order_date, presence: true
  validates :order_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true

  after_save :rollup_customer_deals
  after_destroy :rollup_customer_deals

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  scope :dealt, -> { where.not(status: 'CANCELLED') }

  private

  # 订单号自动生成：SO-YYYYMMDD-NN（当天最大序号+1，删单不回填避免撞号）。显式传入则尊重传入值。
  def generate_order_no
    return if order_no.present?

    prefix = "SO-#{Time.zone.today.strftime('%Y%m%d')}"
    last_seq = account.crm_sales_orders
                      .where('order_no LIKE ?', "#{prefix}-%")
                      .pick(Arel.sql("MAX(SPLIT_PART(order_no, '-', 3)::int)")) || 0
    self.order_no = format('%<prefix>s-%<seq>02d', prefix: prefix, seq: last_seq + 1)
  end

  # 回写客户成交汇总；订单换了客户时，新旧两个客户都要重算。
  def rollup_customer_deals
    customer_ids = [crm_customer_id, crm_customer_id_previously_was].compact.uniq
    Crm::Customer.where(id: customer_ids).find_each(&:recompute_deal_rollup!)
  end
end
