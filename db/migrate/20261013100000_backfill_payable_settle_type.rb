# settle_type 这列上线时全表默认成了「含税」，但公司实际反过来——绝大多数供应商不开票。
# 这个口径系统里早就有：供应商档案的 bill_entity（联合触控＝未税·采购订单，联迪＝含税·采购合同），
# 导出采购单时就按它选模板。所以直接按它回填，不另起一套要人重录的数据。
#
# incurred_on（发生日期）同理：建账时从没写过，全是空的，台账那一列全空。
# 能补的按这张采购单最后一次入库的实际入库日补上，补不到的留空（控制器按建账日兜底）。
class BackfillPayableSettleType < ActiveRecord::Migration[7.1]
  def up
    backfill_supplier_default
    backfill_payable_settle_type
    backfill_payable_incurred_on
  end

  # 回填的是业务口径，撤不回「原来是什么」——原来就是一列没分过的默认值。
  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def backfill_supplier_default
    execute(<<~SQL.squish)
      UPDATE mes_suppliers
         SET default_settle_type = CASE bill_entity WHEN 'liontek' THEN 'PUBLIC' ELSE 'PRIVATE' END
    SQL
  end

  def backfill_payable_settle_type
    execute(<<~SQL.squish)
      UPDATE erp_payables p
         SET settle_type = s.default_settle_type
        FROM mes_suppliers s
       WHERE s.id = p.mes_supplier_id
    SQL
  end

  def backfill_payable_incurred_on
    execute(<<~SQL.squish)
      UPDATE erp_payables p
         SET incurred_on = e.inbound_on
        FROM (
          SELECT purchase_order_id, MAX(actual_inbound_date)::date AS inbound_on
            FROM mes_stock_entries
           WHERE purchase_order_id IS NOT NULL AND actual_inbound_date IS NOT NULL
           GROUP BY purchase_order_id
        ) e
       WHERE e.purchase_order_id = p.mes_purchase_order_id AND p.incurred_on IS NULL
    SQL
  end
end
