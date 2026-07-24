# 个性签名（邮件签名库）：与发信邮箱解耦，一人可建多条命名签名，写邮件时下拉插入。
# 区别于 Crm::Signature（KPI 手写电子签图）——那是图片盖章，这是文字签名。
# == Schema Information
#
# Table name: crm_email_signatures
#
#  id         :bigint           not null, primary key
#  body       :text
#  body_html  :text
#  is_default :boolean          default(FALSE), not null
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  owner_id   :bigint
#
# Indexes
#
#  index_crm_email_signatures_on_account_id  (account_id)
#  index_crm_email_signatures_on_owner_id    (owner_id)
#
class Crm::EmailSignature < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  validates :name, presence: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  # 每个负责人只保留一个默认签名：设为默认时把同一人其余签名撤下。
  after_save :unset_sibling_defaults, if: -> { saved_change_to_is_default? && is_default? }

  private

  def unset_sibling_defaults
    self.class.where(account_id: account_id, owner_id: owner_id)
        .where.not(id: id).where(is_default: true).update_all(is_default: false)
  end
end
