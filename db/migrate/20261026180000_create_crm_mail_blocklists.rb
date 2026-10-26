# 收信黑名单：按发件域名/地址拦掉推销信。
# 原先「标记垃圾邮件」只是把那一封挪进 SPAM 文件夹，不留记忆，下一封照收。
class CreateCrmMailBlocklists < ActiveRecord::Migration[7.0]
  def change
    create_table :crm_mail_blocklists do |t|
      t.bigint :account_id, null: false
      # 不含 @ = 按域名拦（含子域名）；含 @ = 只拦这一个地址。统一存小写。
      t.string :value, null: false
      t.string :note
      t.bigint :created_by_id
      # 拦了多少封、最近一封是谁——拦截是静默丢弃，没有这几个字段就无从判断
      # 规则是写对了还是误伤了。
      t.integer :blocked_count, null: false, default: 0
      t.datetime :last_blocked_at
      t.string :last_blocked_from
      t.string :last_blocked_subject
      t.timestamps
    end
    add_index :crm_mail_blocklists, %i[account_id value], unique: true
  end
end
