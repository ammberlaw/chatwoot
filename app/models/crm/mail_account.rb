# 业务员发信邮箱（SMTP）。对应 A-CRM(Twenty) mailAccount（CRM_SPEC §12.1）。
# 一人可多条，写邮件按 from 匹配；三家企业邮主机内置，自定义填 smtp_host。
# == Schema Information
#
# Table name: crm_mail_accounts
#
#  id             :bigint           not null, primary key
#  email_address  :string           not null
#  imap_enabled   :boolean          default(FALSE), not null
#  imap_host      :string
#  imap_port      :integer
#  imap_ssl       :boolean          default(TRUE), not null
#  imap_synced_at :datetime
#  is_active      :boolean          default(TRUE), not null
#  name           :string           not null
#  provider       :string           default("TENCENT_EXMAIL"), not null
#  signature      :text
#  smtp_host      :string
#  smtp_password  :string
#  smtp_port      :integer
#  smtp_user      :string
#  use_ssl        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  owner_id       :bigint
#
# Indexes
#
#  index_crm_mail_accounts_on_account_id  (account_id)
#  index_crm_mail_accounts_on_owner_id    (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::MailAccount < ApplicationRecord
  PROVIDERS = %w[TENCENT_EXMAIL NETEASE_QIYE ALIYUN_QIYE CUSTOM].freeze
  PROVIDER_HOSTS = {
    'TENCENT_EXMAIL' => 'smtp.exmail.qq.com',
    'NETEASE_QIYE' => 'smtphz.qiye.163.com',
    'ALIYUN_QIYE' => 'smtp.qiye.aliyun.com'
  }.freeze
  # 收件（IMAP）主机；CUSTOM 用 imap_host。认证复用 smtp_password。
  PROVIDER_IMAP_HOSTS = {
    'TENCENT_EXMAIL' => 'imap.exmail.qq.com',
    'NETEASE_QIYE' => 'imaphz.qiye.163.com',
    'ALIYUN_QIYE' => 'imap.qiye.aliyun.com'
  }.freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  encrypts :smtp_password

  validates :name, presence: true
  validates :email_address, presence: true
  validates :provider, inclusion: { in: PROVIDERS }

  scope :active, -> { where(is_active: true) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  # 可收件账户：启用 + 已开 IMAP + 有密码（IMAP 复用 smtp_password 认证）。
  scope :imap_active, -> { active.where(imap_enabled: true).where.not(smtp_password: [nil, '']) }

  def resolved_host
    provider == 'CUSTOM' ? smtp_host : PROVIDER_HOSTS[provider]
  end

  def resolved_imap_host
    provider == 'CUSTOM' ? imap_host : PROVIDER_IMAP_HOSTS[provider]
  end

  def resolved_imap_port
    imap_port || 993
  end

  def resolved_port
    smtp_port || (use_ssl? ? 465 : 587)
  end
end
