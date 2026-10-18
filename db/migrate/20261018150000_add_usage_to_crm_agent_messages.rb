# AI 助手的用量：谁在用、花了多少、跑多久、失败没有。
#
# 原来一概不知道——初筛开了之后它还会自动跑、自动花钱，没有数就既谈不上调优，
# 也判断不了该不该给某个人开。记在 assistant 那条消息上：一问一答算一轮，
# token 是整轮（含中间几次工具调用）的合计。
class AddUsageToCrmAgentMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_agent_messages, :input_tokens, :integer
    add_column :crm_agent_messages, :output_tokens, :integer
    add_column :crm_agent_messages, :duration_ms, :integer
    add_index :crm_agent_messages, [:account_id, :created_at]
  end
end
