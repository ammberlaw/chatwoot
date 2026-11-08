# 获客中心：主动去找客户，而不是等客户上门。
#
# 现状是全被动——近 30 天新增 588 个客户，来源是网站 225 / 阿里 80 / 邮件 62 / 展会 45，
# 没有一条是主动开发来的。
#
# 两张表：
#   crm_lead_campaigns  一次拓客任务（目标市场 + AI 生成的客户画像和关键词）
#   crm_leads           任务搜出来的线索（公司 + 联系人；邮箱按需解锁，不批量烧额度）
class CreateCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_campaigns
    create_leads
    add_indexes
  end

  private

  def create_campaigns
    create_table :crm_lead_campaigns do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id
      t.string :name, null: false
      t.string :status, null: false, default: 'DRAFT'
      t.jsonb :target_markets, null: false, default: []
      t.string :product_hint
      t.string :seed_keywords
      t.integer :target_count, null: false, default: 60
      # AI 出的理想客户画像、本地化关键词，以及「哪几条是真有数据撑着、哪几条是推的」。
      # 最后一项是刻意留的：画像里凭空推断的部分必须标出来，发信之前人要能核实。
      t.jsonb :profile, null: false, default: {}
      t.jsonb :keywords, null: false, default: []
      t.jsonb :evidence, null: false, default: {}
      t.string :run_model
      t.datetime :profiled_at
      t.datetime :searched_at
      t.text :last_error
      t.timestamps
    end
  end

  def create_leads
    create_table :crm_leads do |t|
      t.bigint :account_id, null: false
      t.bigint :crm_lead_campaign_id, null: false
      t.string :status, null: false, default: 'FOUND'
      t.string :company_name
      t.string :domain
      t.string :industry
      t.string :country
      t.string :city
      add_contact_columns(t)
      t.string :apollo_person_id
      # 建档之后挂上去；dup_customer_id 是查重命中的已有客户（不建、直接指过去）。
      t.bigint :crm_customer_id
      t.bigint :dup_customer_id
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
  end

  # 联系人那几列单拎出来：建表方法超过 19 行 rubocop 就拦。
  def add_contact_columns(table)
    table.string :person_name
    table.string :title
    table.string :email
    table.string :email_status
    table.string :linkedin_url
  end

  def add_indexes
    add_index :crm_lead_campaigns, [:account_id, :status]
    add_index :crm_lead_campaigns, :owner_id
    add_index :crm_leads, [:account_id, :crm_lead_campaign_id], name: 'index_crm_leads_on_account_and_campaign'
    add_index :crm_leads, [:account_id, :status]
    add_index :crm_leads, [:account_id, :domain]
    add_index :crm_leads, :apollo_person_id
  end
end
