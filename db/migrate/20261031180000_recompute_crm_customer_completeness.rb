# 资料完整度评分重算（权重变了，见 Crm::CustomerScoring#compute_completeness）。
#
# 分数和等级是**存下来的列**，不重算的话存量客户会一直挂着旧分，
# 只有下次有人保存这条客户才会刷新。
#
# 用 SQL 一条 UPDATE 而不是 find_each + save：
#   · 生产 13231 条，逐条过模型回调又慢又占内存（生产跑 rails runner 会 OOM）；
#   · 小满迁进来的存量客户常带非法值（如 trade_country 不在枚举里），save 会直接校验失败。
# 代价是评分公式在这里复刻了一份——仅此一次性回填用，以模型里那份为准。
#
# 不动 updated_at：客户列表默认按更新时间倒序，刷一遍会把所有人的列表顺序打乱。
class RecomputeCrmCustomerCompleteness < ActiveRecord::Migration[7.1]
  FILLED = ->(col) { "(#{col} IS NOT NULL AND btrim(#{col}) <> '')" }

  SCORE_SQL = <<~SQL.squish
     (CASE WHEN #{FILLED['trade_country']} THEN 8 ELSE 0 END
    + CASE WHEN #{FILLED['website']} THEN 5 ELSE 0 END
    + CASE WHEN #{FILLED['industry']} THEN 4 ELSE 0 END
    + CASE WHEN #{FILLED['trade_region']} OR #{FILLED['trade_city']} THEN 4 ELSE 0 END
    + CASE WHEN #{FILLED['primary_contact_name']} THEN 9 ELSE 0 END
    + CASE WHEN #{FILLED['contact_email']} THEN 20 ELSE 0 END
    + CASE WHEN #{FILLED['whats_app']} OR #{FILLED['wechat']} THEN 10 ELSE 0 END
    + CASE WHEN #{FILLED['contact_phone']} THEN 5 ELSE 0 END
    + CASE WHEN #{FILLED['customer_level']} THEN 7 ELSE 0 END
    + CASE WHEN #{FILLED['product_group']} THEN 8 ELSE 0 END
    + CASE WHEN #{FILLED['source_channel']} THEN 4 ELSE 0 END
    + CASE WHEN #{FILLED['customer_group']} THEN 4 ELSE 0 END
    + CASE WHEN #{FILLED['customer_status']} THEN 7 ELSE 0 END
    + CASE WHEN #{FILLED['customer_remark']} THEN 5 ELSE 0 END)
  SQL

  def up
    execute <<~SQL.squish
      UPDATE crm_customers c SET
        info_completeness_score = sc.s,
        completeness_grade = CASE WHEN sc.s >= 85 THEN 'COMPLETE'
                                  WHEN sc.s >= 60 THEN 'GOOD'
                                  WHEN sc.s >= 40 THEN 'FAIR'
                                  ELSE 'POOR' END
      FROM (SELECT id, #{SCORE_SQL} AS s FROM crm_customers) sc
      WHERE c.id = sc.id
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
