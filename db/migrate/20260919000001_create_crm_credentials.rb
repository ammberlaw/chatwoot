# 文档中心「账号密码」：公司各类账号集中存放，密码字段走 Rails 加密（同邮箱密码）。
#
# 刻意不做成文档中心的一个板块 + 文档：文档正文开了 audited，每改一版都会把旧正文整段
# 留在审计表里，密码会散落多份，还会被文档全文搜索搜到。所以单独建表，正文不进审计。
class CreateCrmCredentials < ActiveRecord::Migration[7.1]
  def change
    # 分组既是归类也是授权单元（「银行/支付」只给财务，「服务器/域名」只给管理员）。
    # 字段与 crm_doc_sections 对齐：viewer_ids 可见成员（空=仅管理员）、manager_ids 可维护成员。
    create_table :crm_credential_groups do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.bigint :viewer_ids, null: false, default: [], array: true
      t.bigint :manager_ids, null: false, default: [], array: true
      t.timestamps
    end
    add_index :crm_credential_groups, [:account_id, :name], unique: true,
                                                            name: 'idx_crm_cred_groups_name'

    create_table :crm_credentials do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_credential_group_id, null: false
      t.string :name, null: false          # 这条账号是干嘛的，如「腾讯企业邮 管理员」
      t.string :url
      t.string :username
      t.text :password                     # encrypts：密文入库，长度按加密后算，用 text
      t.text :note
      t.integer :position, null: false, default: 0
      t.bigint :creator_id
      t.bigint :updated_by_id
      t.timestamps
    end
    add_index :crm_credentials, [:crm_credential_group_id, :position],
              name: 'idx_crm_credentials_group_pos'
    add_foreign_key :crm_credentials, :crm_credential_groups,
                    column: :crm_credential_group_id, on_delete: :cascade

    # 查看留痕：谁在什么时候点开/复制了哪条密码。只增不改，故无 updated_at。
    create_table :crm_credential_views do |t|
      t.references :account, null: false, index: true
      t.bigint :crm_credential_id, null: false
      t.bigint :user_id, null: false
      t.string :action, null: false, default: 'reveal'  # reveal / copy
      t.datetime :created_at, null: false
    end
    add_index :crm_credential_views, [:account_id, :created_at],
              name: 'idx_crm_cred_views_recent'
    add_index :crm_credential_views, :crm_credential_id
    add_foreign_key :crm_credential_views, :crm_credentials,
                    column: :crm_credential_id, on_delete: :cascade
  end
end
