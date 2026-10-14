# CRM 的 AI 助手（agent）：一问一答的对话 + 每次跑的过程留痕。
#
# 和现有那些「点一下做一件事」的 AI 功能（写信/翻译/PI 识别）不同，
# 这个是能自己连着查几步再回答的：查客户 → 翻往来邮件 → 总结 → 起草报价。
# 跑一轮要几十秒、还要调好几次工具，所以放后台任务跑，前端轮询拿结果。
class CreateCrmAgentTables < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_agent_conversations do |t|
      t.bigint :account_id, null: false
      # 对话归属人。agent 取数一律用这个人的权限，不能越权看别人的客户和邮件。
      t.bigint :user_id, null: false
      # 从客户详情面板发起时带上，省得每句话都要报客户名
      t.bigint :crm_customer_id
      t.string :title
      # IDLE 闲着 / RUNNING 正在跑（前端据此轮询）/ FAILED 这轮失败了
      t.string :status, null: false, default: 'IDLE'
      t.text :last_error
      t.timestamps
    end
    add_index :crm_agent_conversations, [:account_id, :user_id]
    add_index :crm_agent_conversations, :crm_customer_id

    create_table :crm_agent_messages do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      # user 我问的 / assistant 它答的 / tool 它中间查了什么（摆出来，不然像黑箱）
      t.string :role, null: false
      t.text :content
      # 工具名、入参、以及产出的草稿 id（邮件草稿/PI 草稿），前端据此给跳转链接
      t.jsonb :meta, null: false, default: {}
      t.timestamps
    end
    add_index :crm_agent_messages, :conversation_id

    # 谁能用这个 agent。空＝只有管理员能用（先小范围试，见 Crm::AiSetting）。
    add_column :crm_ai_settings, :agent_user_ids, :bigint, array: true, null: false, default: []
  end
end
