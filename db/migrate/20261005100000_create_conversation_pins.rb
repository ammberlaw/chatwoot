class CreateConversationPins < ActiveRecord::Migration[7.1]
  def change
    create_table :conversation_pins do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :conversation_id, null: false
      t.timestamps
    end

    # 置顶是「我自己的」，同一个人对同一条会话只能有一条记录
    add_index :conversation_pins, %i[user_id conversation_id], unique: true, name: 'index_conversation_pins_on_user_and_conversation'
    # 列表每次都要按 (当前用户) 左连一次，外加数「我钉了几条」做上限校验
    add_index :conversation_pins, %i[account_id user_id]
    add_index :conversation_pins, :conversation_id
  end
end
