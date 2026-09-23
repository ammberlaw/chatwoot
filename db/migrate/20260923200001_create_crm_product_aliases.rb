# 「记住选择」：明细文字 → 产品档案 的映射。
#
# 业务员给某段客户叫法（PI 上的英文描述、型号简写）选过一次产品后记下来，
# 下次同样文字自动带出。近 180 天 325 行明细只有 207 种不同文字、51% 是重复的，
# 所以这张表能把重复选择的活儿大部分吃掉——包括那 560 个重名产品
#（「863主板」42 条同名，名字本身没区分度，只能靠人选一次然后记住）。
#
# 按账号共享：业务员 A 教会的，业务员 B 也受益。
class CreateCrmProductAliases < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_product_aliases do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.references :crm_product, null: false, foreign_key: { to_table: :crm_products, on_delete: :cascade }
      # 归一化后的明细文字（去空白、转小写）——原文大小写和空格不该影响命中。
      t.string :normalized_text, null: false
      t.string :sample_text
      t.integer :hits, null: false, default: 1
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :crm_product_aliases, [:account_id, :normalized_text], unique: true,
                                                                     name: 'idx_crm_product_aliases_unique'
  end
end
