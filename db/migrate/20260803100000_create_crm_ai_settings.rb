class CreateCrmAiSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_ai_settings do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.text :api_key
      t.string :model, null: false, default: 'deepseek-chat'
      t.string :api_base
      t.timestamps
    end
  end
end
