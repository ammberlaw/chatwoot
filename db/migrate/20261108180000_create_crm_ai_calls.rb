class CreateCrmAiCalls < ActiveRecord::Migration[7.1]
  # AI 调用流水。初筛、背调、简报、写信都在烧 token，而在这之前**一次都没记过**——
  # 要决定这个功能放开给多少人用，手上得有成本数字。
  def change
    create_table :crm_ai_calls do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      # 谁在烧：lead_screen 初筛／lead_bg 背调／lead_digest 简报／lead_profile 画像／mail_* 邮件
      t.string :purpose, null: false
      t.string :model
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :duration_ms
      t.timestamps
    end
    add_index :crm_ai_calls, [:account_id, :created_at]
    add_index :crm_ai_calls, [:account_id, :purpose]
  end
end
