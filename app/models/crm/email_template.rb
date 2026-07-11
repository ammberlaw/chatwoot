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
#  subject_template :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_crm_email_templates_on_account_id  (account_id)
#
class Crm::EmailTemplate < ApplicationRecord
  CATEGORIES = %w[DEVELOPMENT QUOTATION FOLLOW_UP PAYMENT_REMINDER GREETING OTHER].freeze

  belongs_to :account

  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
end
