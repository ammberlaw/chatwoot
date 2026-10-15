# 销售订单。对应 A-CRM(Twenty) 的 salesOrder（CRM_SPEC §2.4/§5/§12.7）。
# 增改删订单会回写所属客户的成交汇总（对应 Twenty 的 customer-deal-rollup 触发器）。
# == Schema Information
#
# Table name: crm_sales_orders
#
#  id                   :bigint           not null, primary key
#  amount_includes_tax  :boolean
#  approval_status      :string           default("APPROVED"), not null
#  approved_at          :datetime
#  cost_amount_micros   :bigint
#  deleted_at           :datetime
#  delivery_date        :datetime
#  exchange_rate        :decimal(12, 6)
#  insurance_order_no   :string
#  line_items           :jsonb            not null
#  name                 :string           not null
#  order_amount_micros  :bigint
#  order_currency       :string           default("CNY")
#  order_date           :datetime         not null
#  order_kind           :string
#  order_no             :string           not null
#  payment_term         :string
#  pi_no                :string
#  profit_amount_micros :bigint
#  profit_rate          :decimal(6, 2)
#  reject_reason        :text
#  remark               :text
#  shipping_micros      :bigint
#  status               :string           default("PENDING_CONFIRMATION"), not null
#  tax_rate             :integer
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  approved_by_id       :bigint
#  contact_id           :bigint
#  crm_customer_id      :bigint
#  crm_opportunity_id   :bigint
#  crm_quote_id         :bigint
#  crm_team_id          :bigint
#  deleted_by_id        :bigint
#  handled_by_id        :bigint
#  owner_id             :bigint
#  receipt_account_id   :bigint
#
# Indexes
#
#  index_crm_sales_orders_on_account_and_insurance_no        (account_id,insurance_order_no) WHERE (insurance_order_no IS NOT NULL)
#  index_crm_sales_orders_on_account_id                      (account_id)
#  index_crm_sales_orders_on_account_id_and_approval_status  (account_id,approval_status)
#  index_crm_sales_orders_on_account_id_and_order_date       (account_id,order_date)
#  index_crm_sales_orders_on_account_id_and_order_kind       (account_id,order_kind)
#  index_crm_sales_orders_on_account_id_and_order_no         (account_id,order_no) UNIQUE
#  index_crm_sales_orders_on_account_id_and_status           (account_id,status)
#  index_crm_sales_orders_on_contact_id                      (contact_id)
#  index_crm_sales_orders_on_crm_customer_id                 (crm_customer_id)
#  index_crm_sales_orders_on_crm_opportunity_id              (crm_opportunity_id)
#  index_crm_sales_orders_on_crm_quote_id                    (crm_quote_id)
#  index_crm_sales_orders_on_crm_team_id                     (crm_team_id)
#  index_crm_sales_orders_on_deleted_at                      (deleted_at)
#  index_crm_sales_orders_on_handled_by_id                   (handled_by_id)
#  index_crm_sales_orders_on_owner_id                        (owner_id)
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
  # 审核：通过了才能转生产订单、才进财务「待建账」（与 status 正交，见 concern 注释）。
  include Crm::SalesOrderApproval

  STATUSES = %w[PENDING_CONFIRMATION IN_PRODUCTION PENDING_SHIPMENT SHIPPED COMPLETED CANCELLED].freeze
  # 给后端消息用（前端各页自己有一份同口径的映射）。
  STATUS_LABELS = { 'PENDING_CONFIRMATION' => '待确认', 'IN_PRODUCTION' => '生产中',
                    'PENDING_SHIPMENT' => '待出货', 'SHIPPED' => '已出货',
                    'COMPLETED' => '已完结', 'CANCELLED' => '已取消' }.freeze

  # 订单双轨（决定一键转单往哪条线走）：
  #   CUSTOM 定制 → 生产订单（走生产脊柱，成本按领料/外协归集）
  #   STOCK  库存 → 现货出库单（直接扣成品库存）
  # 存量订单为空＝未分类，转单时补选。
  ORDER_KINDS = %w[CUSTOM STOCK].freeze
  ORDER_KIND_LABELS = { 'CUSTOM' => '定制单', 'STOCK' => '库存单' }.freeze

  # 折算人民币的金额表达式（现汇买入价锁定在 exchange_rate；CNY/无汇率按 1）。
  # 看板/统计一律用它做 SUM，避免多币种直接混加。列名带表前缀以兼容 join 查询。
  # ⚠️CNY 单必须按 1 折算：历史上人民币单可能残留非 1 汇率（改币种时未清），
  # 若不判币种直接 ×汇率会把 CNY 金额虚增数倍（曾致看板成交额虚高），故按币种守卫。
  # 销项税率：单据上填了就用单据的；没填（历史单、外部导入）按币种推定——
  # 人民币走账套默认税率，美金等外币出口单 0。决定凭证要不要出销项税那一行。
  # 口径见 ERP_SPEC §8.2bis（财务 2026-10-06 拍板）。
  def effective_tax_rate(default_rate = nil)
    return tax_rate if tax_rate.present?
    return 0 unless order_currency.blank? || order_currency == 'CNY'

    default_rate || (account && Erp::Setting.for_account(account).default_output_tax_rate) || 13
  end

  # 订单金额含不含税：单据上填了就用单据的，没填跟随账套默认。
  # 公司两种合同都有（内销常报含税、外贸报不含税），所以不能只在账套上开一个全局开关。
  def effective_amount_includes_tax(default_flag = nil)
    return amount_includes_tax unless amount_includes_tax.nil?
    return default_flag unless default_flag.nil?

    account ? Erp::Setting.for_account(account).amount_includes_tax : true
  end

  # 按 PI 号找回对应的 PI 记录。订单与 PI 之间**没有外键**，只有 pi_no 这个字符串——
  # PI 模块是后来才上的，之前的 PI 都在系统外做，号是手打的。生产上 487 张填了号、
  # 能对上记录的只有 106 张，所以这里恒可能是 nil，调用方必须按「没有」处理。
  def matched_pi
    return nil if pi_no.blank?
    return @matched_pi if defined?(@matched_pi)

    @matched_pi = account.crm_pis.find_by(pi_no: pi_no)
  end

  # 明细里的品名清单（空行、重名都去掉）。应收台账、待建账清单都要「这笔钱是什么货」。
  def product_names
    Array(line_items).filter_map { |item| item.is_a?(Hash) ? item['name'].presence : nil }.uniq
  end

  # 明细行的规范形态（jsonb 里键名不全、类型也不统一，统一在这里收口）。
  # 应收/应付台账要在列表上直接摆出数量单价——以前只有一个「型号」摘要，
  # 财务得逐条点进订单详情才看得到买了什么、什么价。
  def line_item_rows
    Array(line_items).filter_map do |item|
      next unless item.is_a?(Hash)

      { sku: item['sku'], name: item['name'], spec: item['spec'],
        quantity: item['quantity'], unit_price: item['unit_price'], amount: item['amount'] }
    end
  end

  # 首次出库日期：应收的账期多半从货走那天起算，台账上「已出货」却不写日期等于没说。
  def first_shipped_on
    account.mes_shipments.where(crm_sales_order_id: id).where.not(shipped_at: nil).minimum(:shipped_at)&.to_date
  end

  # 首次出库那张单的日期/单号/仓库——应收台账按金蝶口径要「单据日期·单据编号·仓库」三列。
  # 列表页走控制器批量取数，这里只给单条详情用。
  def first_shipment_meta
    shipment = account.mes_shipments.where(crm_sales_order_id: id)
                      .where.not(shipped_at: nil).order(shipped_at: :asc).includes(:warehouse).first
    return {} if shipment.nil?

    { shipped_on: shipment.shipped_at&.to_date, shipment_no: shipment.shipment_no,
      warehouse_name: shipment.warehouse&.name }
  end

  # 明细行的单位/事业部挂在商品档上，订单明细只存了 sku。单条详情用，列表走控制器批量版。
  def product_meta_by_sku
    skus = line_item_rows.pluck(:sku).compact_blank.uniq
    return {} if skus.empty?

    account.crm_products.where(sku: skus).pluck(:sku, :unit, :product_line)
           .to_h { |sku, unit, line| [sku, { unit: unit, product_line: line }] }
  end

  # 列表用的一行摘要：第一项 + 共几项。全部名字走 product_names。
  def product_summary
    names = product_names
    return nil if names.empty?
    return names.first if names.size == 1

    "#{names.first} 等 #{names.size} 项"
  end

  # 客户实付口径的销售额（原币微元）＝ 订单金额 + 运费。
  #
  # 订单金额是**净销售、不含运费**（运费在订单上单独一栏，见 CrmSalesOrderCreateDialog），
  # 但客户打款是一笔钱、货款和运费一起到。ERP 这边只认订单金额的话，应收台账就少一笔
  # 运费：收款核销永远差着尾数，而成本侧偏偏能归集「运费」（付货代的钱）——
  # 只记成本不记收入，毛利凭空被做低。
  #
  # CRM 的业绩/目标口径不走这里（那边用 RMB_AMOUNT_MICROS_SQL 只算订单金额），
  # 运费不算业绩，这个区别是故意的。
  def gross_sales_micros
    order_amount_micros.to_i + shipping_micros.to_i
  end

  # 销售额（含运费）按税率拆成 [不含税收入, 销项税]（原币微元）。
  #
  # 含税单：收入 = 金额 ÷ (1+税率)，税额 = 金额 − 收入，二者之和恒等于销售额；
  # 不含税单：收入 = 金额，税额 = 金额 × 税率，二者之和比销售额多一个税。
  # 税率 0（出口单，生产上 419/501 张）两种算法同值。
  # 运费与货款同税口径，不另按运输服务税率拆——提成表的运费差额也是这么算的。
  def tax_split
    amount = gross_sales_micros
    rate = effective_tax_rate.to_i
    return [amount, 0] if rate <= 0

    if effective_amount_includes_tax
      net = Erp::VoucherLine.round_to_cent(amount * 100.0 / (100 + rate))
      [net, amount - net]
    else
      [amount, Erp::VoucherLine.round_to_cent(amount * rate / 100.0)]
    end
  end

  # 客户实际要付的钱（= 货款 + 运费 + 销项税，原币微元）。
  #
  # 应收台账的建账金额和出库收入凭证的借方必须都取这个数，否则不含税单两边
  # 差一个税额——台账少记税，两账对平(Erp::ReconciliationService)就报一笔
  # 谁也解释不清的差异，而人民币单正好是对平唯一看的那部分。
  def receivable_amount_micros
    net, tax = tax_split
    net + tax
  end

  RMB_AMOUNT_MICROS_SQL = "ROUND(crm_sales_orders.order_amount_micros * CASE WHEN crm_sales_orders.order_currency = 'CNY' THEN 1 ELSE COALESCE(crm_sales_orders.exchange_rate, 1) END)".freeze

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

  # PI 付款自动转单、报价转单等系统内转换：不是人工填的表单，
  # 豁免那些只对人工建单才有意义的必填（附件、订单类型）。
  attr_accessor :system_generated

  before_validation :generate_order_no, on: :create
  before_save :assign_team_from_owner, if: :will_save_change_to_owner_id?
  before_save :lock_exchange_rate

  validates :name, presence: true
  # 唯一性口径必须和数据库索引一致：index_crm_sales_orders_on_account_id_and_order_no
  # 不带 deleted_at 条件，所以已删单的号也仍被占用。之前这里排除了已删单，
  # 校验放过、写库被索引拦下 → 500。
  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :order_date, presence: true
  validates :order_currency, inclusion: { in: Crm::Customer::CURRENCIES }, allow_blank: true
  validates :order_kind, inclusion: { in: ORDER_KINDS }, allow_blank: true
  validates :tax_rate, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
                       allow_nil: true
  validate :require_attachment_on_create, on: :create, unless: :system_generated
  validate :require_order_kind_on_create, on: :create, unless: :system_generated

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

  # 客户成交排行：按「客户 × 月」聚合金额与单数，返回
  # [{ id:, name:, amount: [1..12月], orders: [1..12月] }]。没挂客户的订单不进榜。
  RANK_COLS = "crm_customers.id, crm_customers.name, crm_customers.trade_country, DATE_TRUNC('month', order_date), " \
              "SUM(#{RMB_AMOUNT_MICROS_SQL}), COUNT(*)".freeze

  def self.monthly_customer_ranking(scope)
    month = Arel.sql("DATE_TRUNC('month', order_date)")
    scope.where.not(crm_customer_id: nil).joins(:crm_customer)
         .group('crm_customers.id', 'crm_customers.name', 'crm_customers.trade_country', month).pluck(Arel.sql(RANK_COLS))
         .each_with_object({}) do |(id, name, country, at, amount, count), acc|
      row = acc[id] ||= { id: id, name: name, country: country, amount: Array.new(12, 0), orders: Array.new(12, 0) }
      row[:amount][at.month - 1] = amount.to_i
      row[:orders][at.month - 1] = count.to_i
    end.values
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

  # 订单类型决定这单往下走哪条线（定制→MES 生产订单 / 库存→现货出库单）。
  # 金蝶过渡期它还兼当「这单在哪套系统结算」的标记，空着下游就无从分流，故人工建单必选。
  # 只校验 create：存量未分类的老单照常能改，不逼业务员回填历史。
  def require_order_kind_on_create
    errors.add(:order_kind, '请选择订单类型（定制单/库存单）') if order_kind.blank?
  end

  # 订单所属团队按 owner 自动反写（对应 Twenty sales-order-team-rollup 触发器）。
  def assign_team_from_owner
    self.crm_team_id = owner_id && AccountUser.find_by(account_id: account_id, user_id: owner_id)&.crm_team_id
  end

  # 订单号自动生成：SO-YYYYMMDD-NN（当天最大序号+1，删单不回填避免撞号）。显式传入则尊重传入值。
  def generate_order_no
    return if order_no.present?

    prefix = "SO-#{Time.zone.today.strftime('%Y%m%d')}"
    # 必须绕过 default_scope 把已删单也算进来：唯一索引不认 deleted_at，已删的号还占着。
    # 否则「当天建一单又删掉」之后，后面每一单都算回同一个号、撞索引 500，
    # 连自愈重试都算出同号（当天全员建不了单，实际发生过）。
    last_seq = Crm::SalesOrder.unscoped
                              .where(account_id: account_id)
                              .where('order_no LIKE ?', "#{prefix}-%")
                              .pick(Arel.sql("MAX(SPLIT_PART(order_no, '-', 3)::int)")) || 0
    self.order_no = format('%<prefix>s-%<seq>02d', prefix: prefix, seq: last_seq + 1)
  end

  # 撞号自愈：MAX+1 在并发下会让两单拿到同号，唯一索引拦下后一个抛 RecordNotUnique。
  # 用 savepoint(requires_new) 包住写入，冲突时只回滚本次 INSERT（不牵连外层事务），清号重算重试。
  def create_or_update(*, **)
    attempts = 0
    begin
      self.class.transaction(requires_new: true) { super }
    rescue ActiveRecord::RecordNotUnique => e
      raise unless new_record? && e.message.include?('order_no') && (attempts += 1) <= 5

      self.order_no = nil
      generate_order_no
      retry
    end
  end

  # 回写客户成交汇总；订单换了客户时，新旧两个客户都要重算。
  def rollup_customer_deals
    customer_ids = [crm_customer_id, crm_customer_id_previously_was].compact.uniq
    Crm::Customer.where(id: customer_ids).find_each(&:recompute_deal_rollup!)
  end
end
