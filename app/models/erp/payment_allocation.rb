# 付款核销：把一笔付款拆到一张或多张应付台账上。守恒规则在 Erp::AllocationService。
# == Schema Information
#
# Table name: erp_payment_allocations
#
#  id                :bigint           not null, primary key
#  amount_micros     :bigint           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  payable_id        :bigint           not null
#  payment_record_id :bigint           not null
#
# Indexes
#
#  index_erp_payment_allocations_on_account_id         (account_id)
#  index_erp_payment_allocations_on_payable_id         (payable_id)
#  index_erp_payment_allocations_on_payment_record_id  (payment_record_id)
#
# Foreign Keys
#
#  fk_rails_...  (payable_id => erp_payables.id) ON DELETE => restrict
#  fk_rails_...  (payment_record_id => erp_payment_records.id) ON DELETE => cascade
#
class Erp::PaymentAllocation < ApplicationRecord
  belongs_to :account
  belongs_to :payment_record, class_name: 'Erp::PaymentRecord', inverse_of: :allocations
  belongs_to :payable, class_name: 'Erp::Payable', inverse_of: :allocations

  validates :amount_micros, numericality: { greater_than: 0 }
end
