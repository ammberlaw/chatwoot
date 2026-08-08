# 邮件模板。对应 A-CRM(Twenty) emailTemplate（CRM_SPEC §12.1）。写邮件时套用。
# == Schema Information
#
# Table name: crm_email_templates
#
#  id               :bigint           not null, primary key
#  body             :text
#  category         :string           default("DEVELOPMENT"), not null
#  description      :string
#  name             :string           not null
#  scope            :string           default("COMPANY"), not null
#  subject_template :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  owner_id         :bigint
#
# Indexes
#
#  index_crm_email_templates_on_account_id            (account_id)
#  index_crm_email_templates_on_account_id_and_scope  (account_id,scope)
#  index_crm_email_templates_on_owner_id              (owner_id)
#
class Crm::EmailTemplate < ApplicationRecord
  CATEGORIES = %w[DEVELOPMENT QUOTATION FOLLOW_UP PAYMENT_REMINDER GREETING OTHER].freeze
  # 归属范围：企业模版(全员可用，管理员/副管/主管可管) / 个人模版(创建人私有)。与销售资料同口径。
  SCOPES = %w[COMPANY PERSONAL].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  # 模板附件（如产品目录/报价单）：套用模板时随邮件一起带出。正文内联图片走 body 富文本(HTML)另存 blob。
  has_many_attached :files

  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :scope, inclusion: { in: SCOPES }

  scope :company_templates, -> { where(scope: 'COMPANY') }
  scope :personal_of, ->(user_id) { where(scope: 'PERSONAL', owner_id: user_id) }
end
