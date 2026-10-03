# 外贸客户（公司）档案。Chatwoot 没有原生的「公司/客户账户」实体，
# 因此这是一个全新的模型，对应 A-CRM(Twenty) 中的 company 对象。
# account_owner 为负责人（销售员），公海回收任务会清空它。
# == Schema Information
#
# Table name: crm_customers
#
#  id                       :bigint           not null, primary key
#  address                  :string
#  ai_next_step             :text
#  ai_next_step_at          :datetime
#  alibaba_account          :string
#  completeness_grade       :string
#  contact_email            :string
#  contact_job_title        :string
#  contact_phone            :string
#  contact_preference       :string
#  currency_preference      :string
#  customer_code            :string
#  customer_group           :string
#  customer_level           :string
#  customer_remark          :text
#  customer_status          :string
#  deal_order_count         :integer          default(0), not null
#  deal_total_amount_micros :bigint
#  first_deal_at            :datetime
#  industry                 :string
#  info_completeness_score  :integer          default(0), not null
#  is_in_public_pool        :boolean          default(FALSE), not null
#  last_deal_at             :datetime
#  last_follow_up_at        :datetime
#  linkedin                 :string
#  name                     :string           not null
#  next_follow_up_at        :datetime
#  primary_contact_name     :string
#  product_group            :string
#  public_pool_at           :datetime
#  risk_level               :string
#  shared_user_ids          :bigint           default([]), not null, is an Array
#  source_channel           :string
#  trade_city               :string
#  trade_country            :string
#  trade_region             :string
#  website                  :string
#  wechat                   :string
#  whats_app                :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  account_owner_id         :bigint
#  assigned_by_id           :bigint
#  previous_owner_id        :bigint
#
# Indexes
#
#  index_crm_customers_on_account_id                        (account_id)
#  index_crm_customers_on_account_id_and_alibaba_account    (account_id, lower((alibaba_account)::text))
#  index_crm_customers_on_account_id_and_customer_code      (account_id,customer_code) UNIQUE WHERE (customer_code IS NOT NULL)
#  index_crm_customers_on_account_id_and_customer_status    (account_id,customer_status)
#  index_crm_customers_on_account_id_and_is_in_public_pool  (account_id,is_in_public_pool)
#  index_crm_customers_on_account_id_and_last_follow_up_at  (account_id,last_follow_up_at)
#  index_crm_customers_on_account_owner_id                  (account_owner_id)
#  index_crm_customers_on_shared_user_ids                   (shared_user_ids) USING gin
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::Customer < ApplicationRecord
  include Crm::CustomerScoring
  # 选项集合（对应 A-CRM SELECT 字段的 value 集合）
  TRADE_REGIONS = %w[NORTH_AMERICA EUROPE SOUTH_AMERICA MIDDLE_EAST SOUTHEAST_ASIA AFRICA OTHER].freeze
  INDUSTRIES = %w[RETAIL WHOLESALE DISTRIBUTOR MANUFACTURING ECOMMERCE OTHER].freeze
  CUSTOMER_LEVELS = %w[A B C D].freeze
  # 客户星级：按累计成交额（人民币）自动评定 0–5 星。这 5 个是上切点（元），
  # 与前端 helper/customerStar.js 的 STAR_TIERS_RMB 同口径。
  STAR_TIERS_RMB = [20_000, 100_000, 300_000, 1_000_000, 3_000_000].freeze
  SOURCE_CHANNELS = %w[ALIBABA WEBSITE EXHIBITION REFERRAL EMAIL WHATSAPP OTHER].freeze
  CURRENCIES = %w[USD CNY EUR].freeze
  CUSTOMER_STATUSES = %w[PROSPECT FOLLOWING WON DORMANT LOST].freeze
  CUSTOMER_GROUPS = %w[KEY_ACCOUNT_WON WON SAMPLE_WON NOT_WON SOCIAL_MEDIA].freeze

  # 「最后互动时间」：跟进记录 / 往来邮件 / 下单 / 会话(WhatsApp 等) / 商机动态 五者取最新，
  # 建档时间兜底（新建档不会一上来就判成沉默）。客户列表的「最近联系」、流失预警、
  # 公海自动回收都读这一份，避免各处口径打架——只在一个地方沉默就被收走是最伤业务的。
  LAST_TOUCH_SQL = <<~SQL.squish
    GREATEST(
      crm_customers.created_at,
      COALESCE(crm_customers.last_follow_up_at, crm_customers.created_at),
      COALESCE((SELECT MAX(e.email_date) FROM crm_emails e WHERE e.crm_customer_id = crm_customers.id), crm_customers.created_at),
      COALESCE((SELECT MAX(o.order_date::timestamp) FROM crm_sales_orders o WHERE o.crm_customer_id = crm_customers.id), crm_customers.created_at),
      COALESCE((SELECT MAX(cv.last_activity_at) FROM conversations cv
                  JOIN contacts ct ON ct.id = cv.contact_id
                 WHERE ct.crm_customer_id = crm_customers.id), crm_customers.created_at),
      COALESCE((SELECT MAX(op.last_activity_at) FROM crm_opportunities op WHERE op.crm_customer_id = crm_customers.id), crm_customers.created_at)
    )
  SQL
  # 产品分组两类：平板电脑(TABLET) / 商显工控(COMMERCIAL_DISPLAY，含原商显+工控)。
  PRODUCT_GROUPS = %w[TABLET COMMERCIAL_DISPLAY].freeze
  RISK_LEVELS = %w[LOW MEDIUM HIGH].freeze
  CONTACT_PREFERENCES = %w[EMAIL PHONE WHATSAPP WECHAT].freeze
  COUNTRIES = %w[
    CHINA
    USA GERMANY UK FRANCE ITALY SPAIN CANADA AUSTRALIA
    JAPAN SOUTH_KOREA INDIA RUSSIA BRAZIL MEXICO NETHERLANDS BELGIUM
    SWITZERLAND SWEDEN NORWAY DENMARK FINLAND AUSTRIA POLAND CZECH
    TURKEY UAE SAUDI_ARABIA SINGAPORE MALAYSIA THAILAND VIETNAM INDONESIA
    PHILIPPINES SOUTH_AFRICA ARGENTINA CHILE COLOMBIA PERU ISRAEL EGYPT
    NIGERIA KENYA GREECE PORTUGAL IRELAND NEW_ZEALAND TAIWAN HONG_KONG
    PAKISTAN BANGLADESH UKRAINE ROMANIA HUNGARY BULGARIA CROATIA MOROCCO
    IRAN IRAQ QATAR KUWAIT OMAN MYANMAR CAMBODIA LAOS
    KAZAKHSTAN UZBEKISTAN GHANA SENEGAL ANGOLA ZAMBIA ETHIOPIA CAMEROON
    TANZANIA BENIN SOMALIA TOGO BURKINA_FASO LIBYA BOTSWANA ZIMBABWE
    SOUTH_SUDAN MALI SIERRA_LEONE GUINEA CAPE_VERDE CENTRAL_AFRICAN_REPUBLIC SUDAN MOZAMBIQUE
    MALAWI MAURITIUS ALGERIA TUNISIA IVORY_COAST UGANDA RWANDA GABON
    CONGO DR_CONGO MADAGASCAR NAMIBIA REUNION VENEZUELA COSTA_RICA GUATEMALA
    HAITI HONDURAS EL_SALVADOR BOLIVIA BARBADOS BAHAMAS ECUADOR URUGUAY
    PARAGUAY DOMINICAN_REPUBLIC PANAMA JAMAICA TRINIDAD_AND_TOBAGO CUBA NICARAGUA LEBANON
    JORDAN BAHRAIN YEMEN SYRIA AFGHANISTAN SRI_LANKA NEPAL MONGOLIA
    BRUNEI MALDIVES GEORGIA ARMENIA AZERBAIJAN CYPRUS MALTA LUXEMBOURG
    ICELAND ESTONIA LATVIA LITHUANIA SLOVAKIA SLOVENIA SERBIA BOSNIA
    ALBANIA NORTH_MACEDONIA BELARUS VANUATU FIJI PAPUA_NEW_GUINEA OTHER
  ].freeze

  belongs_to :account
  belongs_to :account_owner, class_name: 'User', optional: true
  # 进公海时记录的原跟进人，供公海列表展示「原跟进人」。
  belongs_to :previous_owner, class_name: 'User', optional: true

  # 审计：记录客户字段的创建/编辑/分配，供「操作历史」展示。
  # 排除自动重算的成交统计与时间戳，避免噪音记录。
  audited except: %i[
    deal_total_amount_micros deal_order_count first_deal_at last_deal_at
    info_completeness_score completeness_grade created_at updated_at
  ], on: %i[create update]

  has_many_attached :files

  # 一个客户多个联系人（Chatwoot Contact，扩展见 Crm::ContactExtensions）
  has_many :contacts, class_name: 'Contact', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  has_many :opportunities, class_name: 'Crm::Opportunity', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  has_many :sales_orders, class_name: 'Crm::SalesOrder', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  has_many :quotes, class_name: 'Crm::Quote', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  has_many :crm_pis, class_name: 'Crm::Pi', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  has_many :emails, class_name: 'Crm::Email', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer
  # 特别关注（每人各标）：客户被哪些人收藏。
  has_many :favorites, class_name: 'Crm::CustomerFavorite', foreign_key: :crm_customer_id, dependent: :delete_all, inverse_of: :customer

  validates :account_id, presence: true
  validates :name, presence: true
  validates :customer_code, uniqueness: { scope: :account_id }, allow_blank: true

  validates :trade_country, inclusion: { in: COUNTRIES }, allow_blank: true
  validates :trade_region, inclusion: { in: TRADE_REGIONS }, allow_blank: true
  validates :industry, inclusion: { in: INDUSTRIES }, allow_blank: true
  validates :customer_level, inclusion: { in: CUSTOMER_LEVELS }, allow_blank: true
  # source_channel / customer_group 现由「客户设置」动态配置（Crm::OptionItem 的 code），故不再做枚举校验。
  validates :currency_preference, inclusion: { in: CURRENCIES }, allow_blank: true
  validates :customer_status, inclusion: { in: CUSTOMER_STATUSES }, allow_blank: true
  validates :product_group, inclusion: { in: PRODUCT_GROUPS }, allow_blank: true
  validates :risk_level, inclusion: { in: RISK_LEVELS }, allow_blank: true
  validates :contact_preference, inclusion: { in: CONTACT_PREFERENCES }, allow_blank: true

  scope :in_public_pool, -> { where(is_in_public_pool: true) }
  scope :assigned, -> { where.not(account_owner_id: nil) }
  scope :owned_by, ->(user_id) { where(account_owner_id: user_id) }
  # 当前用户特别关注的客户。
  scope :favorited_by, ->(user_id) { joins(:favorites).where(crm_customer_favorites: { user_id: user_id }) }
  # 按客户星级筛选（star=0..5 → 累计成交额 micros 区间）。
  scope :by_star, lambda { |star|
    s = star.to_i
    low = s.zero? ? 0 : STAR_TIERS_RMB[s - 1]
    rel = where('COALESCE(deal_total_amount_micros, 0) >= ?', low * 1_000_000)
    rel = rel.where('COALESCE(deal_total_amount_micros, 0) < ?', STAR_TIERS_RMB[s] * 1_000_000) if s < 5
    rel
  }

  # 进公海：清空负责人并记录时间与原归属人（领回冷却期校验用）。供公海回收定时任务与手动操作复用。
  def move_to_public_pool!(at: Time.current)
    update!(is_in_public_pool: true, public_pool_at: at, previous_owner_id: account_owner_id,
            account_owner_id: nil, assigned_by_id: nil)
  end

  # 客户星级 0–5：按累计成交额（人民币）自动评定。deal_total_amount_micros 已是折人民币口径。
  def customer_star
    rmb = (deal_total_amount_micros || 0) / 1_000_000.0
    STAR_TIERS_RMB.count { |tier| rmb >= tier }
  end

  # 成交汇总回写（对应 Twenty customer-deal-rollup 触发器）：
  # 累计成交额 / 成交订单数 / 首次·最近成交时间，口径=非 CANCELLED 订单。
  def recompute_deal_rollup!
    # 多币种订单先折人民币再汇总（与看板/提成同口径），避免美金金额被当人民币直接相加。
    stats = sales_orders.dealt.pick(
      Arel.sql("SUM(#{Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL}), COUNT(*), MIN(order_date), MAX(order_date)")
    )
    # 跳过校验/回调是有意的：缓存统计写回不应触发审计日志或校验。
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      deal_total_amount_micros: stats[0],
      deal_order_count: stats[1] || 0,
      first_deal_at: stats[2],
      last_deal_at: stats[3]
    )
  end

  # 建档录入的联系人：按邮箱建/复用一条 Contact 并挂到本客户，
  # 使采购/经理/客户任一邮箱来信都能识别归属（收信识别走 Contact.crm_customer_id）。
  # 无邮箱的行跳过（识别以邮箱为键）；单个联系人建失败不阻断建档。
  def sync_contacts(entries)
    Array(entries).each do |entry|
      attrs = entry.symbolize_keys
      email = attrs[:email].to_s.strip.downcase
      next if email.blank?

      upsert_contact(email, attrs)
    end
  end

  private

  def upsert_contact(email, attrs)
    contact = account.contacts.where('LOWER(email) = ?', email).first_or_initialize
    contact.email = email if contact.new_record?
    contact.crm_customer_id = id
    contact.name = contact.name.presence || attrs[:name].to_s.strip.presence || email
    contact.is_primary_contact = true if attrs[:is_primary]
    extra = { 'job_title' => attrs[:job_title].to_s.strip.presence, 'phone' => attrs[:phone].to_s.strip.presence }.compact
    contact.additional_attributes = (contact.additional_attributes || {}).merge(extra) if extra.any?
    contact.save!
  rescue ActiveRecord::RecordInvalid
    nil
  end
end
