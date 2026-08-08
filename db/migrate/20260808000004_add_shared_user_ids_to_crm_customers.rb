class AddSharedUserIdsToCrmCustomers < ActiveRecord::Migration[7.1]
  def change
    # 客户协作人：被共享的成员 user_id 列表。被共享者可见该客户（不改归属）。
    add_column :crm_customers, :shared_user_ids, :bigint, array: true, null: false, default: []
    add_index :crm_customers, :shared_user_ids, using: :gin
  end
end
