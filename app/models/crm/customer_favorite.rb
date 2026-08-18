# 客户「特别关注」——每人各标各的（per-user 收藏）。
# == Schema Information
#
# Table name: crm_customer_favorites
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_customer_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_crm_cust_fav_user_customer                          (user_id,crm_customer_id) UNIQUE
#  index_crm_customer_favorites_on_account_id_and_user_id  (account_id,user_id)
#  index_crm_customer_favorites_on_crm_customer_id         (crm_customer_id)
#
class Crm::CustomerFavorite < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :customer, class_name: 'Crm::Customer', foreign_key: :crm_customer_id, inverse_of: :favorites

  validates :user_id, uniqueness: { scope: :crm_customer_id }
end
