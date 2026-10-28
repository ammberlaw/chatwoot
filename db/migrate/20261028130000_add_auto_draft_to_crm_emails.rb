# 老客户来信自动预写回复草稿。
#
# 近 30 天 1265 封来信里，631 封是已建档客户发来的——业务员每天最高频的动作就是回这些信。
# 收信时先替他写一版草稿，他打开邮件时草稿已经在了，改两句就发。
#
# reply_to_email_id：草稿回指原信。两个用处——
#   ① 去重：同一封信只预写一次（收信任务每分钟一轮，重投很常见）
#   ② 界面：打开那封来信时能找到「已经有草稿了」，否则草稿躺在草稿箱里没人知道
# ai_drafted_at：标记这封草稿是机器写的。人工草稿和 AI 草稿在界面上必须分得出来——
#   AI 写的那版默认要被当成「待核对」，不能让人误以为是自己之前写了一半的。
class AddAutoDraftToCrmEmails < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_emails, bulk: true do |t|
      t.bigint :reply_to_email_id
      t.datetime :ai_drafted_at
      # 原信上标记「已经替他预写过了」：和草稿是否还在无关——
      # 他把草稿删了说明不想要，不该下一轮收信又给他写一遍。
      t.datetime :auto_draft_done_at
    end
    add_index :crm_emails, [:account_id, :reply_to_email_id], name: 'index_crm_emails_on_account_reply_to'
  end
end
