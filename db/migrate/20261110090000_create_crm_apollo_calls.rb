class CreateCrmApolloCalls < ActiveRecord::Migration[7.1]
  # Apollo 调用流水。挖公司、抓联系人、解锁邮箱、企业库背调都在烧 credits，
  # 而在这之前**成功的调用一次都没记过**（只有失败才写一行日志）——
  # 于是 Apollo 后台那些数字永远对不到具体动作上，只能靠推。
  #
  # 2026-11-09 就吃过亏：代码注释写着「搜联系人不扣 credits」，实际一轮烧掉 2157 个，
  # 而业务员真正解锁用上的只有 2 个。有了这张表，下个计费周期就能逐笔对账。
  def change
    create_table :crm_apollo_calls do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id
      # 走的哪个端点：mixed_companies_search / mixed_people_search /
      # people_match / organizations_enrich
      t.string :endpoint, null: false
      # 为什么调：lead_search 挖线索／keyword_probe 探词表／contact_fetch 领取抓人／
      # unlock 解锁邮箱／bg_check 背调／name_lookup 按名查公司
      t.string :scene, null: false
      # 返回了几条记录。Apollo 按「导出的记录数」计费，所以这一列才是对账的锚。
      t.integer :returned_count, default: 0, null: false
      t.integer :http_status
      t.integer :duration_ms
      t.timestamps
    end
    add_index :crm_apollo_calls, [:account_id, :created_at]
    add_index :crm_apollo_calls, [:account_id, :scene, :created_at]
  end
end
