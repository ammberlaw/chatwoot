# 快速文本：写邮件时可一键插入正文的个人常用片段（每人私有）。仿小满 OKKI「快速文本」。
# == Schema Information
#
# Table name: crm_quick_texts
#
#  id         :bigint           not null, primary key
#  body       :text
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint           not null
#
# Indexes
#
#  index_crm_quick_texts_on_account_id_and_owner_id  (account_id,owner_id)
#
class Crm::QuickText < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User'

  validates :title, presence: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
end
