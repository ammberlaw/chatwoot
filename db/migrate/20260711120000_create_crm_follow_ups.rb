class CreateCrmFollowUps < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_follow_up_notes do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :contact_id, index: true
      t.bigint :crm_opportunity_id, index: true
      t.bigint :owner_id, index: true
      t.string :title, null: false
      t.text :body
      t.string :follow_up_method
      t.string :result_tag
      t.timestamps
    end

    add_foreign_key :crm_follow_up_notes, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_notes, :contacts, column: :contact_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_notes, :crm_opportunities, column: :crm_opportunity_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_notes, :users, column: :owner_id, on_delete: :nullify

    create_table :crm_follow_up_tasks do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :contact_id, index: true
      t.bigint :crm_opportunity_id, index: true
      t.bigint :assignee_id, index: true
      t.string :title, null: false
      t.text :body
      t.string :status, default: 'TODO', null: false
      t.datetime :due_at
      t.string :task_type
      t.string :related_business_code
      t.timestamps
    end

    add_index :crm_follow_up_tasks, [:account_id, :status]
    add_index :crm_follow_up_tasks, [:account_id, :due_at]
    add_foreign_key :crm_follow_up_tasks, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_tasks, :contacts, column: :contact_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_tasks, :crm_opportunities, column: :crm_opportunity_id, on_delete: :nullify
    add_foreign_key :crm_follow_up_tasks, :users, column: :assignee_id, on_delete: :nullify
  end
end
