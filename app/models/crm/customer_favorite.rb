# 客户「特别关注」——每人各标各的（per-user 收藏）。
class Crm::CustomerFavorite < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :customer, class_name: 'Crm::Customer', foreign_key: :crm_customer_id, inverse_of: :favorites

  validates :user_id, uniqueness: { scope: :crm_customer_id }
end
