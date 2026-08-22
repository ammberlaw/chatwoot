# 邮件链接点击明细（每点一次一条）。聚合计数在 crm_emails.click_count 等列。
# == Schema Information
#
# Table name: crm_email_clicks
#
#  id           :bigint           not null, primary key
#  ip_address   :string
#  url          :string
#  user_agent   :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  crm_email_id :bigint           not null
#
# Indexes
#
#  index_crm_email_clicks_on_crm_email_id  (crm_email_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_email_id => crm_emails.id) ON DELETE => cascade
#
class Crm::EmailClick < ApplicationRecord
  belongs_to :crm_email, class_name: 'Crm::Email', inverse_of: :clicks
end
