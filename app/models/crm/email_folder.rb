# 邮件自定义文件夹（个人私有）：把选中的邮件归集到一起，如某客户的往来邮件。
# == Schema Information
#
# Table name: crm_email_folders
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint           not null
#
# Indexes
#
#  index_crm_email_folders_on_account_id_and_owner_id  (account_id,owner_id)
#
class Crm::EmailFolder < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User'
  has_many :emails, class_name: 'Crm::Email', foreign_key: :crm_email_folder_id, dependent: :nullify, inverse_of: :crm_email_folder

  validates :name, presence: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
end
