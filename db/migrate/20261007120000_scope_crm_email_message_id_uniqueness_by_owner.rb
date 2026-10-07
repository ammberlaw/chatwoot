# 收件判重从「全公司一封信一条」改成「按人一条」。
#
# 原唯一索引 (account_id, message_id) 把一封信在全公司锁成唯一一条：客户发给 A、抄送 B，
# 谁的邮箱先抓到就归谁，B 再抓同一封会撞唯一键 / 被判重丢掉，永远收不到。
# 加上 owner_id 后抄送方各存一份；owner_id 为空的行（历史/发件记录）PG 唯一索引按 NULL 互不相等处理，不受影响。
#
# 新索引比旧索引宽松，旧数据必然满足，不会有冲突。
class ScopeCrmEmailMessageIdUniquenessByOwner < ActiveRecord::Migration[7.1]
  def up
    add_index :crm_emails, [:account_id, :owner_id, :message_id],
              unique: true, where: 'message_id IS NOT NULL',
              name: 'index_crm_emails_on_account_owner_message_id'
    remove_index :crm_emails, name: 'index_crm_emails_on_account_id_and_message_id'
  end

  # 回滚须知：回滚后抄送方那几份会撞回旧唯一索引，建索引会失败。
  # 真要回滚得先删掉本次改动之后新增的抄送副本。
  def down
    add_index :crm_emails, [:account_id, :message_id],
              unique: true, where: 'message_id IS NOT NULL',
              name: 'index_crm_emails_on_account_id_and_message_id'
    remove_index :crm_emails, name: 'index_crm_emails_on_account_owner_message_id'
  end
end
