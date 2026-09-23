# 密码查看留痕。只增不改（表里没有 updated_at），保留 180 天足够复盘，久了自行清理。
# == Schema Information
#
# Table name: crm_credential_views
#
#  id                :bigint           not null, primary key
#  action            :string           default("reveal"), not null
#  created_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_credential_id :bigint           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  idx_crm_cred_views_recent                        (account_id,created_at)
#  index_crm_credential_views_on_account_id         (account_id)
#  index_crm_credential_views_on_crm_credential_id  (crm_credential_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_credential_id => crm_credentials.id) ON DELETE => cascade
#
class Crm::CredentialView < ApplicationRecord
  self.table_name = 'crm_credential_views'

  ACTIONS = %w[reveal copy].freeze

  belongs_to :account
  belongs_to :credential, class_name: 'Crm::Credential', foreign_key: :crm_credential_id,
                          inverse_of: :views
  belongs_to :user

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
end
