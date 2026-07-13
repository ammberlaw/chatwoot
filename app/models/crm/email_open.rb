# 邮件打开明细：追踪像素每被加载一次记一行（时间 + IP + UA）。
# == Schema Information
#
# Table name: crm_email_opens
#
#  id           :bigint           not null, primary key
#  city         :string
#  country      :string
#  ip_address   :string
#  user_agent   :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  crm_email_id :bigint           not null
#
# Indexes
#
#  index_crm_email_opens_on_crm_email_id  (crm_email_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_email_id => crm_emails.id) ON DELETE => cascade
#
class Crm::EmailOpen < ApplicationRecord
  belongs_to :crm_email, class_name: 'Crm::Email'
end
