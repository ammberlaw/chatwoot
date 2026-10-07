# CRM 邮件（收/发/草稿/群发）。对应 A-CRM(Twenty) 的 crmEmail（CRM_SPEC §12.2）。
# 收发件由 CrmEmailListener 从 Chatwoot 邮件渠道消息镜像而来（chatwoot_message_id 去重）；
# 手写草稿/发信（SMTP，S3.6）走 API 直建。
# == Schema Information
#
# Table name: crm_emails
#
#  id                  :bigint           not null, primary key
#  bcc_address         :text
#  body                :text
#  body_html           :text
#  cc_address          :text
#  click_count         :integer          default(0), not null
#  email_date          :datetime
#  first_clicked_at    :datetime
#  first_opened_at     :datetime
#  folder              :string           default("INBOX"), not null
#  from_address        :string
#  is_read             :boolean          default(FALSE), not null
#  is_starred          :boolean          default(FALSE), not null
#  label_ids           :bigint           default([]), not null, is an Array
#  last_clicked_at     :datetime
#  last_opened_at      :datetime
#  open_count          :integer          default(0), not null
#  reply_latency_hours :decimal(10, 2)
#  scheduled_at        :datetime
#  send_error          :text
#  send_now            :boolean          default(FALSE), not null
#  send_status         :string           default("DRAFT"), not null
#  subject             :string
#  to_address          :text
#  tracking_token      :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  chatwoot_message_id :bigint
#  contact_id          :bigint
#  crm_customer_id     :bigint
#  crm_email_folder_id :bigint
#  message_id          :string
#  owner_id            :bigint
#
# Indexes
#
#  index_crm_emails_on_account_id                    (account_id)
#  index_crm_emails_on_account_id_and_email_date     (account_id,email_date)
#  index_crm_emails_on_account_id_and_folder         (account_id,folder)
#  index_crm_emails_on_account_id_and_is_read        (account_id,is_read)
#  index_crm_emails_on_account_owner_message_id      (account_id,owner_id,message_id) UNIQUE WHERE (message_id IS NOT NULL)
#  index_crm_emails_on_chatwoot_message_id           (chatwoot_message_id) UNIQUE WHERE (chatwoot_message_id IS NOT NULL)
#  index_crm_emails_on_contact_id                    (contact_id)
#  index_crm_emails_on_crm_customer_id               (crm_customer_id)
#  index_crm_emails_on_crm_email_folder_id           (crm_email_folder_id)
#  index_crm_emails_on_label_ids                     (label_ids) USING gin
#  index_crm_emails_on_owner_id                      (owner_id)
#  index_crm_emails_on_send_status_and_scheduled_at  (send_status,scheduled_at)
#  index_crm_emails_on_tracking_token                (tracking_token) UNIQUE WHERE (tracking_token IS NOT NULL)
#  index_crm_emails_starred                          (account_id,is_starred) WHERE is_starred
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::Email < ApplicationRecord
  FOLDERS = %w[INBOX SENT DRAFT BULK SPAM].freeze
  # SCHEDULED：定时发送，待 scheduled_at 到点由 DispatchScheduledEmailsJob 转 PENDING。
  SEND_STATUSES = %w[DRAFT SCHEDULED PENDING SENT FAILED].freeze
  # 邮件正文上限（含内联样式/富文本，体积远超普通字段）。收信入库截断与模型校验共用此值，
  # 别再各自写死不同数字（曾出现入库按 2 万截、校验放到 20 万、长邮件被腰斩）。
  BODY_MAX_LENGTH = 200_000

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :crm_email_folder, class_name: 'Crm::EmailFolder', optional: true, inverse_of: :emails

  has_many :opens, class_name: 'Crm::EmailOpen', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  has_many :clicks, class_name: 'Crm::EmailClick', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  has_many :distributions, class_name: 'Crm::EmailDistribution', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  has_many_attached :files

  validates :folder, inclusion: { in: FOLDERS }
  validates :send_status, inclusion: { in: SEND_STATUSES }
  # 邮件正文（含内联样式签名/富文本）体积远超普通字段，显式放宽以跳过全局 20000 text 上限。
  validates :body, length: { maximum: BODY_MAX_LENGTH }
  validates :body_html, length: { maximum: BODY_MAX_LENGTH }

  # 发送触发（对应 Twenty send-email 的 DB 事件）：send_now 归一为 PENDING，
  # 状态刚变成 PENDING 时入队 SMTP 发送；成功/失败由 EmailSendService 回写。
  before_save :normalize_send_now
  after_commit :enqueue_send, if: -> { saved_change_to_send_status? && send_status == 'PENDING' }

  scope :in_folder, ->(folder) { where(folder: folder) }
  scope :unread, -> { where(folder: 'INBOX', is_read: false) }
  scope :starred, -> { where(is_starred: true) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  # 按标签筛选（label_ids 数组列，GIN 索引支撑）。
  scope :with_label, ->(label_id) { where('label_ids @> ARRAY[?]::bigint[]', label_id.to_i) }

  # 会话线程键：把主题反复剥掉 Re:/Fwd:/回复:/答复:/转发: 等前缀后归一（小写、压空白），
  # 同一往来的多封邮件得到同一个键。实时计算，不落库（对存量邮件立即生效）。
  THREAD_PREFIX_RE = /\A\s*(?:re|r\s*e|fw|fwd|答复|回复|回覆|转发|轉發|答覆)\s*[:：]\s*/i

  def self.normalize_thread(subject)
    s = subject.to_s.strip
    loop do
      stripped = s.sub(THREAD_PREFIX_RE, '')
      break if stripped == s

      s = stripped
    end
    s.downcase.gsub(/\s+/, ' ').strip
  end

  # 发信前生成追踪令牌（追踪像素 URL 用），已有则复用。
  def ensure_tracking_token!
    return tracking_token if tracking_token.present?

    # 仅写令牌，无需跑校验/回调（尤其别触发 normalize_send_now / enqueue_send）。
    update_column(:tracking_token, SecureRandom.hex(20)) # rubocop:disable Rails/SkipsModelValidations
    tracking_token
  end

  # 记录一次打开：写明细（含 IP 归属地）+ 累加聚合（首次/最近/次数）。追踪回调走
  # 公开路径，直接原子更新计数列，绕开校验/回调。归属地依赖离线 GeoLite 库，缺库则为空。
  def register_open!(ip:, user_agent:)
    now = Time.current
    geo = Crm::IpGeoResolver.new.resolve(ip)
    opens.create!(ip_address: ip, user_agent: user_agent, country: geo[:country], city: geo[:city])
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      open_count: open_count + 1,
      first_opened_at: first_opened_at || now,
      last_opened_at: now,
      updated_at: now
    )
  end

  # 记录一次链接点击：明细 + 累加聚合。追踪回调走公开路径，绕开校验/回调。
  def register_click!(url:, ip:, user_agent:)
    now = Time.current
    clicks.create!(url: url, ip_address: ip, user_agent: user_agent)
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      click_count: click_count + 1,
      first_clicked_at: first_clicked_at || now,
      last_clicked_at: now,
      updated_at: now
    )
  end

  private

  def normalize_send_now
    self.send_status = 'PENDING' if send_now? && will_save_change_to_send_now?
  end

  def enqueue_send
    Crm::SendEmailJob.perform_later(id)
  end
end
