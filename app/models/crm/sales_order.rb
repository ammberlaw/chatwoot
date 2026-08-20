# 销售订单。对应 A-CRM(Twenty) 的 salesOrder（CRM_SPEC §2.4/§5/§12.7）。
# 增改删订单会回写所属客户的成交汇总（对应 Twenty 的 customer-deal-rollup 触发器）。
# == Schema Information
#
# Table name: crm_sales_orders
#
#  id                   :bigint           not null, primary key
#  cost_amount_micros   :bigint
#  deleted_at           :datetime
#  delivery_date        :datetime
#  exchange_rate        :decimal(12, 6)
#  line_items           :jsonb            not null
#  name                 :string           not null
#  order_amount_micros  :bigint
#  order_currency       :string           default("CNY")
#  order_date           :datetime         not null
#  order_no             :string           not null
#  pi_no                :string
#  profit_amount_micros :bigint
#  profit_rate          :decimal(6, 2)
#  remark               :text
#  shipping_micros      :bigint
#  status               :string           default("PENDING_CONFIRMATION"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  contact_id           :bigint
#  crm_customer_id      :bigint
#  crm_opportunity_id   :bigint
#  crm_quote_id         :bigint
#  crm_team_id          :bigint
#  deleted_by_id        :bigint
#  handled_by_id        :bigint
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
#  index_crm_sales_orders_on_crm_quote_id               (crm_quote_id)
#  index_crm_sales_orders_on_crm_team_id                (crm_team_id)
#  index_crm_sales_orders_on_deleted_at                 (deleted_at)
#  index_crm_sales_orders_on_handled_by_id              (handled_by_id)
#  index_crm_sales_orders_on_owner_id                   (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (crm_opportunity_id => crm_opportunities.id) ON DELETE => nullify
#  fk_rails_...  (crm_quote_id => crm_quotes.id) ON DELETE => nullify
#  fk_rails_...  (crm_team_id => crm_teams.id) ON DELETE => nullify
#  fk_rails_...  (handled_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::SalesOrder < ApplicationRecord
  STATUSES = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT SHIPPED COMPLETED CANCELLED].freeze

  # 折算人民币的金额表达式（现汇买入价锁定在 exchange_rate；CNY/无汇率按 1）。
  # 看板/统计一律用它做 SUM，避免多币种直接混加。列名带表前缀以兼容 join 查询。
  RMB_AMOUNT_MICROS_SQL = 'ROUND(crm_sales_orders.order_amount_micros * COALESCE(crm_sales_orders.exchange_rate, 1))'.freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :crm_opportunity, class_name: 'Crm::Opportunity', optional: true
  belongs_to :quote, class_name: 'Crm::Quote', foreign_key: :crm_quote_id, optional: true, inverse_of: :sales_orders
  belongs_to :owner, class_name: 'User', optional: true
  # 经办人：实际建单的人（业绩仍归 owner=客户归属人，此字段仅留痕）。
  belongs_to :handled_by, class_name: 'User', optional: true
  belongs_to :crm_team, class_name: 'Crm::Team', optional: true, inverse_of: :sales_orders
  # 软删除人（回收箱展示）。
  belongs_to :deleted_by, class_name: 'User', optional: true

  # 审计：记录订单的创建/编辑，供详情面板「操作历史」展示。
  audited except: %i[created_at updated_at], on: %i[create update]

  # 订单附件（PI、生产订单等）。新建订单强制至少一个附件。
  has_many_attached :files

  # PI 付款自动转单等系统内转换：单据即 PI 本身，豁免「必须带附件」硬校验。
  attr_accessor :skip_attachment_check

  before_validation :generate_order_no, on: :create
  before_save :assign_team_from_owner, if: :will_save_change_to_owner_id?
  before_save :lock_exchange_rate

  validates :name, presence: true
  validates :order_no, presence: true,
                       uniqueness: { scope: :account_id, conditions: -> { where(deleted_at: nil) } }
  validates :status, inclusion: { in: STATUSES }
  validates :order_date, presence: true
  validates :order_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true
  validate :require_attachment_on_create, on: :create, unless: :skip_attachment_check

  after_destroy :rollup_customer_deals
  after_save :rollup_customer_deals

  # 软删除：默认只查未删单（看板/统计/列表/客户成交额一律自动排除已删），
  # 回收箱用 only_deleted（去掉默认条件后取已删）。
  default_scope { where(deleted_at: nil) }
  scope :only_deleted, -> { unscope(where: :deleted_at).where.not(deleted_at: nil) }

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  scope :dealt, -> { where.not(status: 'CANCELLED') }
  scope :completed, -> { where(status: 'COMPLETED') }

  # 软删除 / 恢复。删除后 after_save 触发客户成交额重算（已删不再计入）。
  def soft_delete!(user)
    update!(deleted_at: Time.current, deleted_by_id: user&.id)
  end

  def restore!
    update!(deleted_at: nil, deleted_by_id: nil)
  end

  private

  # 外币订单锁定「做单当日」中行现汇买入价折算汇率；手填优先。
  # 当日及之前无牌价时（如订单日期早于 FX 历史起点）回退到最早可得牌价，避免留空被当 1:1 不换算。
  def lock_exchange_rate
    return if order_currency.blank? || order_currency == 'CNY'
    return if exchange_rate.present?

    on = order_date || Time.zone.today
    rate = Crm::FxRate.rate_for(order_currency, on) || Crm::FxRate.rate_on_or_after(order_currency, on)
    self.exchange_rate = rate if rate
  end

  # 新建订单必须至少上传一个附件（如 PI、生产订单）。
  def require_attachment_on_create
    errors.add(:files, '请至少上传一个附件（如 PI、生产订单）') unless files.attached?
  end

  # 订单所属团队按 owner 自动反写（对应 Twenty sales-order-team-rollup 触发器）。
  def assign_team_from_owner
    self.crm_team_id = owner_id && AccountUser.find_by(account_id: account_id, user_id: owner_id)&.crm_team_id
  end

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
