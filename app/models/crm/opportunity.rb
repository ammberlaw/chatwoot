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
#  next_follow_up_at   :datetime
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
  # 5 阶段：需求确认(已报价) / 样品中 / 待付款 / 已成交 / 输单。待付款为推进态(非终态)。
  SALES_STAGES = %w[NEEDS_CONFIRMED SAMPLING PENDING_PAYMENT WON LOST].freeze
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

  # 商机「最后动静」。这一列过去从来没有人写过（上线至今生产 181 条全是空的），
  # 而客户的「最后互动」(Crm::Customer::LAST_TOUCH_SQL) 把它算作一路来源——
  # 空着就等于这一路恒等于建档时间，白占一格。
  #
  # 口径＝**商机本身被推进过**（阶段、金额、下一步、备注…任一实质字段变化），
  # 不含该客户的邮件往来和下单：那两路在 LAST_TOUCH_SQL 里各自有来源，
  # 混进来会让「商机多久没动」永远看不出停滞。
  ACTIVITY_IGNORED_ATTRS = %w[last_activity_at updated_at].freeze

  before_save :stamp_last_activity

  def amount
    amount_micros.to_f / 1_000_000 if amount_micros
  end

  # 按「今日最新中行牌价」折算成人民币的金额（micros）。看板混币列汇总用：
  # 不同币种的商机不能直接相加，需先统一折算为 CNY。CNY 原样返回；查不到牌价返回 nil。
  # 同一请求内相同币种的牌价查询会命中 ActiveRecord query cache，不产生 N+1。
  def amount_cny_micros
    return nil if amount_micros.nil?
    return amount_micros if currency.blank? || currency == 'CNY'

    # 优先取今日(含之前)最近牌价；该币种只有更晚的牌价时(如刚启用)回退到最近的一条，
    # 避免外币商机因暂无历史牌价被静默排除出人民币汇总，导致看板金额偏低。
    rate = Crm::FxRate.rate_for(currency, Date.current) || Crm::FxRate.rate_on_or_after(currency, Date.current)
    rate && (amount_micros * rate).round
  end

  private

  def stamp_last_activity
    return if (changed - ACTIVITY_IGNORED_ATTRS).empty?

    self.last_activity_at = Time.current
  end
end
