class AddAdjustmentToPayrollItems < ActiveRecord::Migration[7.1]
  def change
    # 规则外的个别调整。2026-09 表里就有两处藏在公式里的手工改动
    # （一行应发公式末尾硬加 +29，一行补贴少算 136.36），
    # 没有这个栏位，下次还得去改公式——改完没人知道改了什么、为什么改。
    add_column :crm_payroll_items, :adjustment_micros, :bigint, null: false, default: 0
    add_column :crm_payroll_items, :adjustment_reason, :string
  end
end
