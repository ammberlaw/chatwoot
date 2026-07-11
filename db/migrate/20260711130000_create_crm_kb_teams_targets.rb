class CreateCrmKbTeamsTargets < ActiveRecord::Migration[7.1]
  def change
    # 知识库（CRM_SPEC §12.1 knowledgeBase）
    create_table :crm_knowledge_docs do |t|
      t.references :account, null: false, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      t.string :category
      t.string :summary
      t.string :scope, default: 'PERSONAL', null: false
      t.text :body
      t.timestamps
    end
    add_index :crm_knowledge_docs, [:account_id, :scope]
    add_index :crm_knowledge_docs, [:account_id, :category]
    add_foreign_key :crm_knowledge_docs, :users, column: :owner_id, on_delete: :nullify

    # 销售团队（CRM_SPEC §12.1 team）
    create_table :crm_teams do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.bigint :team_lead_id, index: true
      t.timestamps
    end
    add_foreign_key :crm_teams, :users, column: :team_lead_id, on_delete: :nullify

    # 业务员归属团队（Twenty workspaceMember.team ≈ Chatwoot AccountUser）
    add_column :account_users, :crm_team_id, :bigint
    add_index :account_users, :crm_team_id
    add_foreign_key :account_users, :crm_teams, column: :crm_team_id, on_delete: :nullify

    # 订单所属团队（sales-order-team-rollup：按 owner 自动反写，看板按团队统计）
    add_column :crm_sales_orders, :crm_team_id, :bigint
    add_index :crm_sales_orders, :crm_team_id
    add_foreign_key :crm_sales_orders, :crm_teams, column: :crm_team_id, on_delete: :nullify

    # 业绩目标（CRM_SPEC §12.1 salesTarget）
    create_table :crm_sales_targets do |t|
      t.references :account, null: false, index: true
      t.bigint :owner_id, index: true
      t.string :name, null: false
      t.datetime :target_month, null: false
      t.bigint :target_amount_micros
      t.integer :target_order_count
      t.timestamps
    end
    add_index :crm_sales_targets, [:account_id, :target_month]
    add_foreign_key :crm_sales_targets, :users, column: :owner_id, on_delete: :nullify
  end
end
