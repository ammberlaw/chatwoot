# 外贸客户（公司）档案。Chatwoot 没有原生的「公司/客户账户」实体，
# 因此这是一个全新的模型，对应 A-CRM(Twenty) 中的 company 对象。
# account_owner 为负责人（销售员），公海回收任务会清空它。
class Crm::Customer < ApplicationRecord
  # 选项集合（对应 A-CRM SELECT 字段的 value 集合）
  TRADE_REGIONS = %w[NORTH_AMERICA EUROPE SOUTH_AMERICA MIDDLE_EAST SOUTHEAST_ASIA AFRICA OTHER].freeze
  INDUSTRIES = %w[RETAIL WHOLESALE DISTRIBUTOR MANUFACTURING ECOMMERCE OTHER].freeze
  CUSTOMER_LEVELS = %w[A B C D].freeze
  SOURCE_CHANNELS = %w[ALIBABA WEBSITE EXHIBITION REFERRAL EMAIL OTHER].freeze
  CURRENCIES = %w[USD CNY EUR].freeze
  CUSTOMER_STATUSES = %w[PROSPECT FOLLOWING WON DORMANT LOST].freeze
  CUSTOMER_GROUPS = %w[KEY_ACCOUNT_WON WON SAMPLE_WON NOT_WON SOCIAL_MEDIA].freeze
  PRODUCT_GROUPS = %w[TABLET COMMERCIAL_DISPLAY INDUSTRIAL_CONTROL].freeze
  RISK_LEVELS = %w[LOW MEDIUM HIGH].freeze
  CONTACT_PREFERENCES = %w[EMAIL PHONE WHATSAPP WECHAT].freeze
  COUNTRIES = %w[
    USA GERMANY UK FRANCE ITALY SPAIN CANADA AUSTRALIA JAPAN SOUTH_KOREA INDIA RUSSIA BRAZIL MEXICO
    NETHERLANDS BELGIUM SWITZERLAND SWEDEN NORWAY DENMARK FINLAND AUSTRIA POLAND CZECH TURKEY UAE
    SAUDI_ARABIA SINGAPORE MALAYSIA THAILAND VIETNAM INDONESIA PHILIPPINES SOUTH_AFRICA ARGENTINA
    CHILE COLOMBIA PERU ISRAEL EGYPT NIGERIA KENYA GREECE PORTUGAL IRELAND NEW_ZEALAND TAIWAN
    HONG_KONG PAKISTAN BANGLADESH UKRAINE ROMANIA HUNGARY BULGARIA CROATIA MOROCCO IRAN IRAQ QATAR
    KUWAIT OMAN MYANMAR CAMBODIA LAOS KAZAKHSTAN UZBEKISTAN OTHER
  ].freeze

  belongs_to :account
  belongs_to :account_owner, class_name: 'User', optional: true

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
end
