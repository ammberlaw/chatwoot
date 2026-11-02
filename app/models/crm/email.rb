# CRM 邮件（收/发/草稿/群发）。对应 A-CRM(Twenty) 的 crmEmail（CRM_SPEC §12.2）。
# 收发件由 CrmEmailListener 从 Chatwoot 邮件渠道消息镜像而来（chatwoot_message_id 去重）；
# 手写草稿/发信（SMTP，S3.6）走 API 直建。
# == Schema Information
#
# Table name: crm_emails
#
#  id                        :bigint           not null, primary key
#  ai_drafted_at             :datetime
#  ai_triaged_at             :datetime
#  auto_draft_done_at        :datetime
#  bcc_address               :text
#  body                      :text
#  body_html                 :text
#  cc_address                :text
#  click_count               :integer          default(0), not null
#  email_date                :datetime
#  first_clicked_at          :datetime
#  first_opened_at           :datetime
#  folder                    :string           default("INBOX"), not null
#  from_address              :string
#  is_read                   :boolean          default(FALSE), not null
#  is_starred                :boolean          default(FALSE), not null
#  label_ids                 :bigint           default([]), not null, is an Array
#  last_clicked_at           :datetime
#  last_opened_at            :datetime
#  open_count                :integer          default(0), not null
#  reply_latency_hours       :decimal(10, 2)
#  scheduled_at              :datetime
#  send_error                :text
#  send_now                  :boolean          default(FALSE), not null
#  send_status               :string           default("DRAFT"), not null
#  sender_utc_offset_minutes :integer
#  subject                   :string
#  to_address                :text
#  tracking_token            :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  chatwoot_message_id       :bigint
#  contact_id                :bigint
#  crm_customer_id           :bigint
#  crm_email_folder_id       :bigint
#  message_id                :string
#  owner_id                  :bigint
#  reply_to_email_id         :bigint
#
# Indexes
#
#  index_crm_emails_on_account_id                    (account_id)
#  index_crm_emails_on_account_id_and_ai_triaged_at  (account_id,ai_triaged_at)
#  index_crm_emails_on_account_id_and_email_date     (account_id,email_date)
#  index_crm_emails_on_account_id_and_folder         (account_id,folder)
#  index_crm_emails_on_account_id_and_is_read        (account_id,is_read)
#  index_crm_emails_on_account_owner_message_id      (account_id,owner_id,message_id) UNIQUE WHERE (message_id IS NOT NULL)
#  index_crm_emails_on_account_reply_to              (account_id,reply_to_email_id)
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
  #
  # 2026-10-20 从 20 万提到 100 万：外贸一条线程来回十几轮是常态，而引用链每轮都把
  # 上一封整个 body_html 裹进来；企业邮箱（阿里尤其）给每个节点都挂内联样式，
  # HTML 大约是纯文本的 5 倍。生产上已有 7 封真撞上限被截断（分布在 4 条线程，
  # 最早 10-07），其中一条回到第 13 轮就发不出去了，报「Body html过长」。
  #
  # 提这个数的前提是**列表不再下发正文**（见 _crm_email.json.jbuilder 的 detail 开关）：
  # 原来一页 25 封全带正文、平均每封 1.8 万字，放开上限会让列表响应跟着膨胀。
  # 现在列表只给 body_preview，正文在点开那一封时单独拉。
  BODY_MAX_LENGTH = 1_000_000

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :crm_email_folder, class_name: 'Crm::EmailFolder', optional: true, inverse_of: :emails

  has_many :opens, class_name: 'Crm::EmailOpen', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  has_many :clicks, class_name: 'Crm::EmailClick', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  has_many :distributions, class_name: 'Crm::EmailDistribution', foreign_key: :crm_email_id, inverse_of: :crm_email, dependent: :destroy
  # 群发给每个收件人各建一封邮件，附件**共用同一个 blob**（见 EmailsController#bulk_create）。
  # 所以删一封不能把文件直接删掉——别的收件人那几封还指着它。
  # dependent: false 关掉 ActiveStorage 的默认 purge，改由 purge_unshared_files 判断：
  # 只有没人再引用的 blob 才真删，还有人用的只摘掉这条引用。
  has_many_attached :files, dependent: false

  validates :folder, inclusion: { in: FOLDERS }
  validates :send_status, inclusion: { in: SEND_STATUSES }
  # 邮件正文（含内联样式签名/富文本）体积远超普通字段，显式放宽以跳过全局 20000 text 上限。
  validates :body, length: { maximum: BODY_MAX_LENGTH }
  validates :body_html, length: { maximum: BODY_MAX_LENGTH }

  # 发送触发（对应 Twenty send-email 的 DB 事件）：send_now 归一为 PENDING，
  # 状态刚变成 PENDING 时入队 SMTP 发送；成功/失败由 EmailSendService 回写。
  before_save :normalize_send_now
  before_destroy :purge_unshared_files, prepend: true
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

  # 删邮件时清理附件：blob 还被别的记录引用（群发共用）就只摘引用，否则连文件一起清。
  def purge_unshared_files
    files_attachments.each do |attachment|
      if ActiveStorage::Attachment.where(blob_id: attachment.blob_id).where.not(id: attachment.id).exists?
        attachment.delete
      else
        attachment.purge_later
      end
    end
  end

  # ⚠️ 这里原来写的是 `send_now? && will_save_change_to_send_now?`——只认 send_now
  # **从 false 翻成 true 的那一次**。于是记录一旦落到 (send_now=true, DRAFT)，
  # 再点发送时 send_now 没有「变化」，这条永不触发、信永远发不出去，界面上的表现
  # 就是「点了发送又变回草稿」。2026-11-02 生产上卡了 3 封（#6538 当天的那封）。
  #
  # 怎么落到那个状态的：草稿自动保存会把 send_status 原样 PATCH 回 DRAFT
  # （控制器放行客户端传的 send_status），而 send_now 还留着 true——sidekiq 停摆
  # 那两天信在队列里排着没发完，人回去改草稿，就把 PENDING 盖成了 DRAFT。
  def normalize_send_now
    # 显式改回草稿＝撤回这次发送，send_now 要跟着落下来，别留下自相矛盾的状态。
    if will_save_change_to_send_status? && send_status == 'DRAFT'
      self.send_now = false
      return
    end

    # 不看「是否刚翻成 true」，只看「现在要发、且还没在队列里」——
    # 中间漏过一次入队，之后任何一次保存都还能把它重新推上去。
    self.send_status = 'PENDING' if send_now? && send_status != 'PENDING'
  end

  def enqueue_send
    Crm::SendEmailJob.perform_later(id)
  end
end
