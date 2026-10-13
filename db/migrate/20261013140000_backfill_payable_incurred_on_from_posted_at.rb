class BackfillPayableIncurredOnFromPostedAt < ActiveRecord::Migration[7.1]
  # 上一支迁移只认 actual_inbound_date，而原料采购入库单上没有这一栏（只有成品入库才录），
  # 结果一条也没回填上。改按过账时间兜底——仓管点过账就是确认货到那一刻。
  def up
    execute(<<~SQL.squish)
      UPDATE erp_payables p
         SET incurred_on = e.inbound_on
        FROM (
          SELECT purchase_order_id,
                 MAX(COALESCE(actual_inbound_date, posted_at))::date AS inbound_on
            FROM mes_stock_entries
           WHERE purchase_order_id IS NOT NULL
             AND status = 'POSTED'
             AND COALESCE(actual_inbound_date, posted_at) IS NOT NULL
           GROUP BY purchase_order_id
        ) e
       WHERE e.purchase_order_id = p.mes_purchase_order_id
         AND p.incurred_on IS NULL
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
