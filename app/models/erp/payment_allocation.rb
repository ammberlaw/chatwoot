# 付款核销：把一笔付款拆到一张或多张应付台账上。守恒规则在 Erp::AllocationService。
class Erp::PaymentAllocation < ApplicationRecord
  belongs_to :account
  belongs_to :payment_record, class_name: 'Erp::PaymentRecord', inverse_of: :allocations
  belongs_to :payable, class_name: 'Erp::Payable', inverse_of: :allocations

  validates :amount_micros, numericality: { greater_than: 0 }
end
