class CreateCrmOpportunities < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_opportunities do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      # 金额沿用 Twenty 口径：整数微分（1 元 = 1_000_000），S4 数据迁移可 1:1 直搬
      t.bigint :amount_micros
      t.string :currency, default: 'CNY'
      t.string :sales_stage, default: 'INITIAL_CONTACT', null: false
      t.integer :probability
      t.datetime :expected_close_date
      t.text :current_need
      t.string :competitor
      t.string :loss_reason
      t.string :next_action
      t.datetime :last_activity_at
      t.text :opportunity_remark
      t.timestamps
    end

    # 商机漏斗按阶段分列 / 看板聚合
    add_index :crm_opportunities, [:account_id, :sales_stage]
    add_foreign_key :crm_opportunities, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_opportunities, :users, column: :owner_id, on_delete: :nullify
  end
end
