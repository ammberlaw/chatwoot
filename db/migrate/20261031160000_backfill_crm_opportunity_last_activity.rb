# 商机「最后动静」回填。这列自上线起从没被写过（生产 181 条全空），
# 而它是客户「最后互动」(Crm::Customer::LAST_TOUCH_SQL) 的来源之一，空着这一路就恒等于建档时间。
# 存量没有逐次修改的历史可追，取 updated_at 作为「最后一次被动过」的近似；
# 之后由 Crm::Opportunity#stamp_last_activity 持续维护。
class BackfillCrmOpportunityLastActivity < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE crm_opportunities
         SET last_activity_at = GREATEST(created_at, updated_at)
       WHERE last_activity_at IS NULL
    SQL
  end

  def down
    # 回填不可逆：原值全是 NULL，但清回 NULL 会把回填后产生的真实动静一起抹掉。
    raise ActiveRecord::IrreversibleMigration
  end
end
