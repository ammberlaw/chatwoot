class AddApolloQuota < ActiveRecord::Migration[7.1]
  # Apollo 积分是买断的，用完就没有。能扣积分的只有「解锁联系方式」一步，
  # 所以按人按月给额度，并记下每条是谁什么时候解的——没有这两列就既算不出用量，
  # 也查不出积分花在哪了。
  def change
    add_column :crm_leads, :unlocked_by_id, :bigint
    add_column :crm_leads, :unlocked_at, :datetime
    add_index :crm_leads, [:unlocked_by_id, :unlocked_at]

    # 全公司每月上限；每人每月默认上限；个别人的单独额度 { "用户id" => 条数 }。
    add_column :crm_ai_settings, :apollo_monthly_limit, :integer
    add_column :crm_ai_settings, :apollo_user_limit, :integer
    add_column :crm_ai_settings, :apollo_user_limits, :jsonb, default: {}, null: false
  end
end
