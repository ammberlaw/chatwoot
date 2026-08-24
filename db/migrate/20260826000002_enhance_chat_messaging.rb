class EnhanceChatMessaging < ActiveRecord::Migration[7.1]
  def change
    # @提及：被 @ 到的成员 user_id 列表（GIN 便于「@我的未读」查询）。
    add_column :chat_messages, :mentioned_ids, :bigint, array: true, default: [], null: false
    add_index :chat_messages, :mentioned_ids, using: :gin

    # 业务对象进群：一条消息可附带一个 CRM 对象引用（客户/订单等）。
    # ref_snapshot 存发送时的标题/编号快照，渲染卡片不必回查（也避免越权拉数据）。
    add_column :chat_messages, :ref_type, :string
    add_column :chat_messages, :ref_id, :bigint
    add_column :chat_messages, :ref_snapshot, :jsonb
  end
end
