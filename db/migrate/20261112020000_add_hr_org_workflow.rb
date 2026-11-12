class AddHrOrgWorkflow < ActiveRecord::Migration[7.1]
  def change
    add_column :org_departments, :archived_at, :datetime
    add_column :account_users, :org_managed_crm_role, :boolean, default: false, null: false
    add_column :account_users, :org_previous_crm_role, :string
    add_column :crm_employee_comps, :active, :boolean, default: true, null: false
    add_column :crm_employee_comps, :effective_on, :date
    add_reference :crm_employee_comps, :previous_comp, foreign_key: { to_table: :crm_employee_comps, on_delete: :restrict }
    create_table :crm_hr_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :employee, foreign_key: { to_table: :crm_employees, on_delete: :nullify }
      t.references :department, foreign_key: { to_table: :org_departments, on_delete: :nullify }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :user_id
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    create_table :crm_offboarding_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :employee, foreign_key: { to_table: :crm_employees, on_delete: :nullify }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :user_id, null: false
      t.bigint :target_user_id
      t.string :mode, null: false
      t.string :status, null: false, default: 'pending'
      t.string :error_message
      t.jsonb :summary, null: false, default: {}
      t.datetime :completed_at
      t.timestamps
      t.index [:account_id, :user_id, :status], name: 'idx_offboarding_user_status'
    end
  end
end
