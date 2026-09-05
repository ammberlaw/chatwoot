class AddUniqueOrderToCrmCommissionItems < ActiveRecord::Migration[7.1]
  # 一张销售订单只能进一张提成表：对 (account_id, crm_sales_order_id) 加部分唯一索引
  # （手填行 crm_sales_order_id 为空，不受约束）。杜绝并发/多标签导入把同一单计入两张表重复算提成。
  def change
    add_index :crm_commission_items, %i[account_id crm_sales_order_id],
              unique: true, where: 'crm_sales_order_id IS NOT NULL',
              name: 'uniq_commission_item_order'
  end
end
