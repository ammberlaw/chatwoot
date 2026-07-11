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
#  email_date          :datetime
#  folder              :string           default("INBOX"), not null
#  from_address        :string
#  is_read             :boolean          default(FALSE), not null
#  reply_latency_hours :decimal(10, 2)
#  send_error          :text
#  send_now            :boolean          default(FALSE), not null
#  send_status         :string           default("DRAFT"), not null
#  subject             :string
#  to_address          :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  chatwoot_message_id :bigint
#  contact_id          :bigint
#  crm_customer_id     :bigint
#  owner_id            :bigint
#
# Indexes
#
#  index_crm_emails_on_account_id                 (account_id)
#  index_crm_emails_on_account_id_and_email_date  (account_id,email_date)
#  index_crm_emails_on_account_id_and_folder      (account_id,folder)
#  index_crm_emails_on_account_id_and_is_read     (account_id,is_read)
#  index_crm_emails_on_chatwoot_message_id        (chatwoot_message_id) UNIQUE WHERE (chatwoot_message_id IS NOT NULL)
#  index_crm_emails_on_contact_id                 (contact_id)
#  index_crm_emails_on_crm_customer_id            (crm_customer_id)
#  index_crm_emails_on_owner_id                   (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (crm_customer_id => crm_customers.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::Email < ApplicationRecord
  FOLDERS = %w[INBOX SENT DRAFT BULK].freeze
  SEND_STATUSES = %w[DRAFT PENDING SENT FAILED].freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :contact, optional: true
  belongs_to :owner, class_name: 'User', optional: true

  has_many_attached :files

  validates :folder, inclusion: { in: FOLDERS }
  validates :send_status, inclusion: { in: SEND_STATUSES }

  scope :in_folder, ->(folder) { where(folder: folder) }
  scope :unread, -> { where(folder: 'INBOX', is_read: false) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
end
