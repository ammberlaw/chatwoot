# 外贸客户（公司）档案。Chatwoot 没有原生的「公司/客户账户」实体，
# 因此这是一个全新的模型，对应 A-CRM(Twenty) 中的 company 对象。
# account_owner 为负责人（销售员），公海回收任务会清空它。
# == Schema Information
#
# Table name: crm_customers
#
#  id                       :bigint           not null, primary key
#  address                  :string
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
#
# Indexes
#
#  index_crm_customers_on_account_id                        (account_id)
#  index_crm_customers_on_account_id_and_customer_code      (account_id,customer_code) UNIQUE WHERE (customer_code IS NOT NULL)
#  index_crm_customers_on_account_id_and_customer_status    (account_id,customer_status)
#  index_crm_customers_on_account_id_and_is_in_public_pool  (account_id,is_in_public_pool)
#  index_crm_customers_on_account_id_and_last_follow_up_at  (account_id,last_follow_up_at)
#  index_crm_customers_on_account_owner_id                  (account_owner_id)
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
  SOURCE_CHANNELS = %w[ALIBABA WEBSITE EXHIBITION REFERRAL EMAIL OTHER].freeze
  CURRENCIES = %w[USD CNY EUR].freeze
  CUSTOMER_STATUSES = %w[PROSPECT FOLLOWING WON DORMANT LOST].freeze
  CUSTOMER_GROUPS = %w[KEY_ACCOUNT_WON WON SAMPLE_WON NOT_WON SOCIAL_MEDIA].freeze
  # 商显与工控已合并为「商显工控」（COMMERCIAL_DISPLAY），不再区分。
  PRODUCT_GROUPS = %w[TABLET COMMERCIAL_DISPLAY].freeze
  RISK_LEVELS = %w[LOW MEDIUM HIGH].freeze
  CONTACT_PREFERENCES = %w[EMAIL PHONE WHATSAPP WECHAT].freeze
  COUNTRIES = %w[
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
  has_many :emails, class_name: 'Crm::Email', foreign_key: :crm_customer_id, dependent: :nullify, inverse_of: :crm_customer

  validates :account_id, presence: true
  validates :name, presence: true
  validates :customer_code, uniqueness: { scope: :account_id }, allow_blank: true

  validates :trade_country, inclusion: { in: COUNTRIES }, allow_blank: true
  validates :trade_region, inclusion: { in: TRADE_REGIONS }, allow_blank: true
  validates :industry, inclusion: { in: INDUSTRIES }, allow_blank: true
  validates :customer_level, inclusion: { in: CUSTOMER_LEVELS }, allow_blank: true
  validates :source_channel, inclusion: { in: SOURCE_CHANNELS }, allow_blank: true
  validates :currency_preference, inclusion: { in: CURRENCIES }, allow_blank: true
  validates :customer_status, inclusion: { in: CUSTOMER_STATUSES }, allow_blank: true
  validates :customer_group, inclusion: { in: CUSTOMER_GROUPS }, allow_blank: true
  validates :product_group, inclusion: { in: PRODUCT_GROUPS }, allow_blank: true
  validates :risk_level, inclusion: { in: RISK_LEVELS }, allow_blank: true
  validates :contact_preference, inclusion: { in: CONTACT_PREFERENCES }, allow_blank: true

  scope :in_public_pool, -> { where(is_in_public_pool: true) }
  scope :assigned, -> { where.not(account_owner_id: nil) }
  scope :owned_by, ->(user_id) { where(account_owner_id: user_id) }

  # 进公海：清空负责人并记录时间。供公海回收定时任务与手动操作复用。
  def move_to_public_pool!(at: Time.current)
    update!(is_in_public_pool: true, public_pool_at: at, account_owner_id: nil)
  end

  # 成交汇总回写（对应 Twenty customer-deal-rollup 触发器）：
  # 累计成交额 / 成交订单数 / 首次·最近成交时间，口径=非 CANCELLED 订单。
  def recompute_deal_rollup!
    stats = sales_orders.dealt.pick(Arel.sql('SUM(order_amount_micros), COUNT(*), MIN(order_date), MAX(order_date)'))
    # 跳过校验/回调是有意的：缓存统计写回不应触发审计日志或校验。
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      deal_total_amount_micros: stats[0],
      deal_order_count: stats[1] || 0,
      first_deal_at: stats[2],
      last_deal_at: stats[3]
    )
  end
end
