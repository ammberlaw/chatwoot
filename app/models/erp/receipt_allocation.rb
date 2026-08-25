# 收款核销：把一笔收款拆到一张或多张应收台账上。守恒规则在 Erp::AllocationService。
class Erp::ReceiptAllocation < ApplicationRecord
  belongs_to :account
  belongs_to :receipt_record, class_name: 'Erp::ReceiptRecord', inverse_of: :allocations
  belongs_to :receivable, class_name: 'Erp::Receivable', inverse_of: :allocations

  validates :amount_micros, numericality: { greater_than: 0 }
end
