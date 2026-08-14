class AddSoftDeleteToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    # 软删除：deleted_at 非空即在回收箱；deleted_by_id 记录删除人（回收箱展示）。
    add_column :crm_sales_orders, :deleted_at, :datetime
    add_column :crm_sales_orders, :deleted_by_id, :bigint
    add_index :crm_sales_orders, :deleted_at
  end
end
