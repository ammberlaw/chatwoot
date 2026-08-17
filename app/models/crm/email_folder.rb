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
#  parent_id  :bigint
#
# Indexes
#
#  index_crm_email_folders_on_account_id_and_owner_id  (account_id,owner_id)
#  index_crm_email_folders_on_parent_id                (parent_id)
#
class Crm::EmailFolder < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User'
  # 自嵌套：支持无限层级子文件夹。删父级连子级一起删（其邮件 nullify 回系统视图）。
  belongs_to :parent, class_name: 'Crm::EmailFolder', optional: true
  has_many :children, class_name: 'Crm::EmailFolder', foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  has_many :emails, class_name: 'Crm::Email', foreign_key: :crm_email_folder_id, dependent: :nullify, inverse_of: :crm_email_folder

  validates :name, presence: true
  validate :parent_not_self

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  private

  def parent_not_self
    errors.add(:parent_id, '不能设为自身') if parent_id.present? && parent_id == id
  end
end
