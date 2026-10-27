# AI 助手的跨对话记忆。
#
# 现在每开一个新对话就从零开始：你说过「写邮件别那么啰嗦」，下次照样啰嗦；
# 纠正过一次的口径，它不会沉淀。日常用它的人会反复教同一件事。
#
# 刻意做得很小：一人几十条短句，开场全量注入，不做向量检索那一套——
# 几十条直接塞进提示词就够，上检索是给还不存在的规模付代价。
class CreateCrmAgentMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_agent_memories do |t|
      t.bigint :account_id, null: false
      # 记忆按人隔离：这是「你的习惯」，不是公司知识。别人的偏好串进来会更糟。
      t.bigint :user_id, null: false
      t.text :content, null: false
      # 哪一轮对话里记下来的，便于回溯「这条是怎么来的」
      t.bigint :source_conversation_id
      t.timestamps
    end

    add_index :crm_agent_memories, [:account_id, :user_id, :created_at],
              name: 'index_crm_agent_memories_on_account_user_time'
  end
end
