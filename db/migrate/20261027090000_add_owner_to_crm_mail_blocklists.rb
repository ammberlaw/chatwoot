# 黑名单分两级：owner_id 为空＝全公司生效（管理员配），有值＝只拦投递到这个人名下的信。
#
# 原先只有全公司一级、且限管理员维护。实查却是：标过垃圾邮件的只有肖天海一个人
# （业务员，25 封 8 个域名）——唯一在用的人恰恰被关在门外，等于这功能没人能用。
class AddOwnerToCrmMailBlocklists < ActiveRecord::Migration[7.0]
  def change
    add_column :crm_mail_blocklists, :owner_id, :bigint
    add_index :crm_mail_blocklists, :owner_id

    # 原唯一索引没有 owner 维度，两个人拉黑同一个域名会撞。拆成两条：
    remove_index :crm_mail_blocklists, column: %i[account_id value]
    # 个人规则：同一个人同一个值只许一条。
    add_index :crm_mail_blocklists, %i[account_id owner_id value],
              unique: true, where: 'owner_id IS NOT NULL',
              name: 'idx_crm_mail_blocklists_owner_value'
    # 全公司规则：PG 把 NULL 当互不相同，不加 where 的话同一个值能插进去好几条。
    add_index :crm_mail_blocklists, %i[account_id value],
              unique: true, where: 'owner_id IS NULL',
              name: 'idx_crm_mail_blocklists_global_value'
  end
end
