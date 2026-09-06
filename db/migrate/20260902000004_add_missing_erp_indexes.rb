class AddMissingErpIndexes < ActiveRecord::Migration[7.1]
  def change
    # 凭证列表每行都要反查「本张被谁红冲了」（has_one :reversed_by），没索引就是整表扫描。
    add_index :erp_vouchers, :reversal_of_id

    # 维度明细账按部门/业务员切片、期末调汇按维度分组都要用；
    # 客户/供应商/订单三个维度早就有索引，这两个当初漏了。
    add_index :erp_voucher_lines, :department_id
    add_index :erp_voucher_lines, :member_id
  end
end
