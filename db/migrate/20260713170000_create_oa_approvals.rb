class CreateOaApprovals < ActiveRecord::Migration[7.1]
  def change
    create_templates
    create_requests
    create_steps
  end

  def create_templates
    create_table :oa_approval_templates do |t|
      t.bigint :account_id, null: false, index: true
      t.string :name, null: false
      t.string :description
      t.string :icon, default: 'i-lucide-file-check'
      t.jsonb :form_fields, default: [], null: false
      t.jsonb :flow, default: [], null: false
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
  end

  def create_requests
    create_table :oa_approval_requests do |t|
      t.bigint :account_id, null: false, index: true
      t.references :template, null: false, foreign_key: { to_table: :oa_approval_templates, on_delete: :cascade }
      t.bigint :applicant_id, null: false, index: true
      t.string :title, null: false
      t.jsonb :form_data, default: {}, null: false
      t.string :status, default: 'pending', null: false
      t.integer :current_position, default: 0, null: false
      t.datetime :submitted_at
      t.timestamps
      t.index [:account_id, :status]
    end
  end

  def create_steps
    create_table :oa_approval_steps do |t|
      t.bigint :account_id, null: false, index: true
      t.references :request, null: false, foreign_key: { to_table: :oa_approval_requests, on_delete: :cascade }
      t.integer :position, null: false
      t.bigint :approver_id, index: true
      t.string :status, default: 'pending', null: false
      t.text :comment
      t.datetime :acted_at
      t.timestamps
    end
  end
end
