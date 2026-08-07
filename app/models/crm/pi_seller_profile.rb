# PI 卖方预录：每个业务员录一份自己的对外落款联系方式（联系人 / 手机 / 邮箱）。
# 新建 PI 时带入这份预录到 PI 的卖方快照（issued_by / seller_mobile / seller_email），
# 之后改预录不影响已开 PI。导出 Excel 的卖方抬头 idx1/idx2 与 ISSUED BY 用 PI 快照填。
# == Schema Information
#
# Table name: crm_pi_seller_profiles
#
#  id           :bigint           not null, primary key
#  contact_name :string
#  email        :string
#  mobile       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  owner_id     :bigint
#
# Indexes
#
#  idx_crm_pi_seller_profiles_account_owner  (account_id,owner_id) UNIQUE
#
class Crm::PiSellerProfile < ApplicationRecord
  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  validates :contact_name, presence: true
  validates :mobile, presence: true
  validates :email, presence: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
end
