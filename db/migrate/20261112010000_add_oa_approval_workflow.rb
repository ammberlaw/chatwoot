class AddOaApprovalWorkflow < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :oa_approval_templates, :revision, :integer, default: 1, null: false
    add_column :oa_approval_templates, :auto_approve, :boolean, default: false, null: false
    add_column :oa_approval_templates, :overdue_hours, :integer, default: 24, null: false
    add_column :oa_approval_requests, :template_snapshot, :jsonb, default: {}, null: false
    add_column :oa_approval_requests, :integration_result, :jsonb, default: {}, null: false
    add_column :oa_approval_requests, :finalized_at, :datetime
    add_column :oa_approval_requests, :submission_key, :string
    add_column :oa_approval_requests, :source_request_id, :bigint
    add_column :oa_approval_requests, :last_reminded_at, :datetime
    add_column :oa_approval_steps, :assigned_at, :datetime
    add_index :oa_approval_requests, [:account_id, :applicant_id, :submission_key], unique: true,
                                   where: 'submission_key IS NOT NULL', name: 'idx_oa_submission_key', algorithm: :concurrently
    add_index :oa_approval_requests, :source_request_id, algorithm: :concurrently
    add_foreign_key :oa_approval_requests, :oa_approval_requests, column: :source_request_id, on_delete: :restrict, validate: false
    validate_foreign_key :oa_approval_requests, :oa_approval_requests, column: :source_request_id
    remove_foreign_key :oa_approval_requests, column: :template_id
    add_foreign_key :oa_approval_requests, :oa_approval_templates, column: :template_id, on_delete: :restrict, validate: false
    validate_foreign_key :oa_approval_requests, :oa_approval_templates, column: :template_id
    create_table :oa_approval_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :request, null: false, foreign_key: { to_table: :oa_approval_requests, on_delete: :cascade }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false
      t.jsonb :payload, default: {}, null: false
      t.timestamps
    end
    create_table :oa_approval_cc_receipts do |t|
      t.references :request, null: false, foreign_key: { to_table: :oa_approval_requests, on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :read_at
      t.timestamps
    end
    add_index :oa_approval_cc_receipts, [:request_id, :user_id], unique: true, name: 'idx_oa_cc_receipt'
  end

  def down
    drop_table :oa_approval_cc_receipts
    drop_table :oa_approval_events
    remove_foreign_key :oa_approval_requests, column: :template_id
    add_foreign_key :oa_approval_requests, :oa_approval_templates, column: :template_id, on_delete: :cascade
    remove_reference :oa_approval_requests, :source_request, foreign_key: { to_table: :oa_approval_requests }
    %i[template_snapshot integration_result finalized_at submission_key last_reminded_at].each { |column| remove_column :oa_approval_requests, column }
    remove_column :oa_approval_steps, :assigned_at
    %i[revision auto_approve overdue_hours].each { |column| remove_column :oa_approval_templates, column }
  end
end
