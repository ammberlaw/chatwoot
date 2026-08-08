class CreateCrmQuickTexts < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_quick_texts do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id, null: false # 个人私有：每人只见/管自己的快速文本
      t.string :title, null: false
      t.text :body
      t.timestamps
    end
    add_index :crm_quick_texts, [:account_id, :owner_id]
  end
end
