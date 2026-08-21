class CreateCrmEmailLabels < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_email_labels do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :color, null: false, default: 'slate'
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :crm_email_labels, [:account_id, :name], unique: true

    # 邮件所打标签（引用 crm_email_labels.id）。沿用本仓库既有惯例（shared_user_ids 等）用数组列，
    # 不建 join 表；GIN 索引支撑「按标签筛选」(label_ids @> ARRAY[id])。
    add_column :crm_emails, :label_ids, :bigint, array: true, null: false, default: []
    add_index :crm_emails, :label_ids, using: :gin
  end
end
