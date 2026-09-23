# 账号密码分「公司」与「我的」两档（同知识库的公司文档/我的文档）：
#
#   owner_id 为空 = 公司条目：挂在分组下，可见范围由分组的 viewer_ids/manager_ids 决定，
#                   每次查看/复制都留痕。
#   owner_id 有值 = 个人条目：创建人独占（管理员也看不到），不分组、不留痕——
#                   自己看自己的密码，记录下来只会把公司条目的审计日志淹掉。
#
# 因此分组外键改为可空：个人条目没有分组。
class AddOwnerToCrmCredentials < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_credentials, :owner_id, :bigint
    add_index :crm_credentials, [:account_id, :owner_id], name: 'idx_crm_credentials_owner'
    change_column_null :crm_credentials, :crm_credential_group_id, true
  end
end
