# 信保订单号：阿里巴巴国际站的信保单。和水单号（reference_no，银行那边的流水）
# 不是一回事——同一笔钱两边各有各的编号，对账时两个都要能查。
class AddTradeAssuranceNoToErpReceiptRecords < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_receipt_records, :trade_assurance_no, :string
    add_index :erp_receipt_records, [:account_id, :trade_assurance_no],
              name: 'index_erp_receipt_records_on_account_and_trade_assurance'
  end
end
