# 展会名片：现场拍 → 后台识别 → 回头批量校对 → 确认建客户。
#
# 为什么要这张中间表、不直接建客户：展会一天几十张名片，现场网络差、人嘈杂，
# 逐张核对填表根本来不及；而名片上的信息又不足以直接开档（没有国家、没有需求、
# 常常一家公司来好几个人）。直接进客户库会把库污染掉，事后合并比重录还贵。
# 所以先把照片抢下来，识别交给后台慢慢跑，校对放回酒店或公司再做。
# == Schema Information
#
# Table name: crm_business_cards
#
#  id              :bigint           not null, primary key
#  address         :text
#  company_name    :string
#  contact_email   :string
#  contact_name    :string
#  contact_phone   :string
#  country         :string
#  event_name      :string
#  job_title       :string
#  parse_error     :text
#  parsed_at       :datetime
#  raw_text        :text
#  remark          :text
#  status          :string           default("PENDING"), not null
#  website         :string
#  whats_app       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_customer_id :bigint
#  owner_id        :bigint           not null
#
# Indexes
#
#  index_crm_business_cards_on_account_id             (account_id)
#  index_crm_business_cards_on_account_id_and_status  (account_id,status)
#  index_crm_business_cards_on_crm_customer_id        (crm_customer_id)
#  index_crm_business_cards_on_owner_id               (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id)
#
class Crm::BusinessCard < ApplicationRecord
  # PENDING 待识别（刚传上来）/ PARSED 已识别待校对 / CONFIRMED 已建客户 / DISCARDED 不要了
  STATUSES = %w[PENDING PARSED CONFIRMED DISCARDED].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User'
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true

  # 名片照片。一张卡一张图；重拍就换掉（整组替换语义，这里本来就只有一张）。
  has_one_attached :image

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where.not(status: 'DISCARDED') }
  scope :inbox, -> { where(status: %w[PENDING PARSED]) }

  # 识别出来的可编辑字段：控制器的 strong params、校对保存、建客户三处共用这一份，
  # 免得加一个字段要改三个地方还漏掉。
  EDITABLE_FIELDS = %w[
    company_name contact_name job_title contact_phone whats_app
    contact_email website country address event_name remark
  ].freeze

  # 建客户时带过去的字段（名片字段名 → 客户字段名）。字段名两边不一样，
  # 照抄会静默丢数据（客户表没有 contact_name/country/remark 这几个列）。
  # event_name 和 remark 不在这里：它们并进客户备注，见 #customer_remark。
  CUSTOMER_FIELD_MAP = {
    'company_name' => :name,
    'contact_name' => :primary_contact_name,
    'job_title' => :contact_job_title,
    'contact_email' => :contact_email,
    'contact_phone' => :contact_phone,
    'whats_app' => :whats_app,
    'website' => :website,
    'country' => :trade_country,
    'address' => :address
  }.freeze

  # 够不够格建客户：客户表只有公司名必填，这里跟它保持一致。
  def ready_to_confirm? = company_name.to_s.strip.present?

  # 建档备注：把名片上没有、只有现场才知道的东西串起来——
  # 哪个展会收的、当场聊了什么。职位单独有列（contact_job_title），不往这里塞。
  def customer_remark
    [event_name.presence && "展会：#{event_name}", remark.presence].compact.join('；').presence
  end
end
