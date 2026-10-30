# 记忆原来一律按人隔离。但公司级的规矩（「报价一律 FOB 深圳」「别叫 Dear Sir」）
# 每个人各教一遍不现实，所以加一档 ACCOUNT：管理员记一条，全公司都带着。
class AddScopeToCrmAgentMemories < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_agent_memories, :scope, :string, null: false, default: 'USER'
    add_index :crm_agent_memories, [:account_id, :scope, :created_at],
              name: 'index_crm_agent_memories_on_account_scope_time'
  end
end
