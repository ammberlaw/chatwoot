class CreateCrmApolloTags < ActiveRecord::Migration[7.1]
  # Apollo 标签词表的本地缓存。
  #
  # 探词（mixed_companies_count）原来只在一次搜索的内存里缓存，每跑一轮任务就
  # 新建一个 resolver、之前探过的词全部重探——同一个 digital signage 在 11 个任务里
  # 探了 11 遍。2026-11-10 台账：探词调用 406 次，而全公司实际用到的不同词才两百来个。
  #
  # 标签存不存在是**全局且稳定**的事实（不随国家、不随任务变），落库之后一个词只探一次。
  def change
    create_table :crm_apollo_tags do |t|
      t.bigint :account_id, null: false
      # 人/模型写的原话（归一化后）
      t.string :phrase, null: false
      # 探出来的真实标签；nil = 词表里确实没有，别再探了
      t.string :tag
      # 该标签全球挂着多少家公司，用于判断值不值得退到更糙的词
      t.integer :total
      t.integer :probes, default: 0, null: false
      t.timestamps
    end
    add_index :crm_apollo_tags, [:account_id, :phrase], unique: true
  end
end
