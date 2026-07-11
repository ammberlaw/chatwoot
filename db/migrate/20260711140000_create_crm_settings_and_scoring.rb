class CreateCrmSettingsAndScoring < ActiveRecord::Migration[7.1]
  def change
    # 公海规则设置（单行配置，CRM_SPEC §12.1 publicPoolSetting）
    create_table :crm_public_pool_settings do |t|
      t.references :account, null: false, index: { unique: true }
      t.string :name, default: '客户池规则'
      t.integer :stale_days, default: 90, null: false
      t.boolean :recycle_enabled, default: true, null: false
      t.boolean :recycle_never_followed, default: false, null: false
      t.integer :pool_limit_key_account_won
      t.integer :pool_limit_won
      t.integer :pool_limit_sample_won
      t.integer :pool_limit_not_won
      t.integer :pool_limit_social_media
      t.timestamps
    end

    # 客户补列：官网(打分项)、完善度评分/等级（CRM_SPEC §12.3）
    change_table :crm_customers, bulk: true do |t|
      t.string :website
      t.integer :info_completeness_score, default: 0, null: false
      t.string :completeness_grade
    end
  end
end
