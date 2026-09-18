# 定制报价的转交记录：谁把单子推给了谁、为什么。
# 单独一张表而不是塞 jsonb，是因为「这单在谁手上流转过」后面要能查、能统计。
# == Schema Information
#
# Table name: crm_quote_request_transfers
#
#  id           :bigint           not null, primary key
#  reason       :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  from_user_id :bigint
#  request_id   :bigint           not null
#  to_user_id   :bigint           not null
#
# Indexes
#
#  index_crm_quote_request_transfers_on_account_id  (account_id)
#  index_crm_quote_request_transfers_on_request_id  (request_id)
#
class Crm::QuoteRequestTransfer < ApplicationRecord
  belongs_to :account
  belongs_to :request, class_name: 'Crm::QuoteRequest'
  belongs_to :from_user, class_name: 'User', optional: true
  belongs_to :to_user, class_name: 'User'

  validates :to_user_id, presence: true
end
