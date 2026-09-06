# 收款核销：把一笔收款拆到一张或多张应收台账上。守恒规则在 Erp::AllocationService。
# == Schema Information
#
# Table name: erp_receipt_allocations
#
#  id                :bigint           not null, primary key
#  amount_micros     :bigint           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  receipt_record_id :bigint           not null
#  receivable_id     :bigint           not null
#
# Indexes
#
#  index_erp_receipt_allocations_on_account_id         (account_id)
#  index_erp_receipt_allocations_on_receipt_record_id  (receipt_record_id)
#  index_erp_receipt_allocations_on_receivable_id      (receivable_id)
#
# Foreign Keys
#
#  fk_rails_...  (receipt_record_id => erp_receipt_records.id) ON DELETE => cascade
#  fk_rails_...  (receivable_id => erp_receivables.id) ON DELETE => restrict
#
class Erp::ReceiptAllocation < ApplicationRecord
  belongs_to :account
  belongs_to :receipt_record, class_name: 'Erp::ReceiptRecord', inverse_of: :allocations
  belongs_to :receivable, class_name: 'Erp::Receivable', inverse_of: :allocations

  validates :amount_micros, numericality: { greater_than: 0 }
end
