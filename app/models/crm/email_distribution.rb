# 邮件内部分发记录：谁把哪封邮件分发给了谁（站内流转，不外发）。每个被分发人一行。
# == Schema Information
#
# Table name: crm_email_distributions
#
#  id           :bigint           not null, primary key
#  note         :text
#  read_at      :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  crm_email_id :bigint           not null
#  from_user_id :bigint           not null
#  to_user_id   :bigint           not null
#
# Indexes
#
#  idx_crm_email_dist_email_user                               (crm_email_id,to_user_id) UNIQUE
#  index_crm_email_distributions_on_account_id_and_to_user_id  (account_id,to_user_id)
#  index_crm_email_distributions_on_crm_email_id               (crm_email_id)
#
class Crm::EmailDistribution < ApplicationRecord
  belongs_to :account
  belongs_to :crm_email, class_name: 'Crm::Email'
  belongs_to :from_user, class_name: 'User'
  belongs_to :to_user, class_name: 'User'

  validates :to_user_id, uniqueness: { scope: :crm_email_id }

  scope :to_user, ->(uid) { where(to_user_id: uid) }
end
