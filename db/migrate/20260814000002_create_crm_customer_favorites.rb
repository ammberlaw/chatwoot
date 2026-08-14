class CreateCrmCustomerFavorites < ActiveRecord::Migration[7.1]
  def change
    # 客户「特别关注」——每人各标各的（per-user 收藏），仿小满爱心。
    create_table :crm_customer_favorites do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :crm_customer_id, null: false
      t.timestamps
    end
    add_index :crm_customer_favorites, %i[user_id crm_customer_id], unique: true,
                                       name: 'idx_crm_cust_fav_user_customer'
    add_index :crm_customer_favorites, :crm_customer_id
    add_index :crm_customer_favorites, %i[account_id user_id]
  end
end
