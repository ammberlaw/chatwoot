# 物料标准价回填：每颗料取**最近一次**审批通过、未作废的采购单价。
#
# 这张表生产上一条都没有（2026-10-29 财务提「采购单价没有数据库」，页面上那个
# 「从采购单回填」按钮至今没人点过），而 355 颗料在采购单里本来就有真实成交价。
# 空着的后果：生产任务单算成本时「标准价」这一级永远落空，一路掉到最近采购价兜底。
#
# 口径与 MaterialPricesController#backfill_from_purchases 和
# Mes::MaterialPriceResolver 的「最近采购价」完全一致（审批通过、未作废、有价），
# 所以回填进来的数和任务单上原本兜底显示的是同一个。
#
# ⚠️ 只填**空缺**：本表已经有的那颗料一律跳过，不拿采购价盖掉财务手工维护的标准价。
# updated_by_id 留空——这批不是哪个人改的，备注里写明了来源。
class BackfillMesMaterialPricesFromPurchases < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      INSERT INTO mes_material_prices
        (account_id, crm_product_id, unit_price_micros, remark, created_at, updated_at)
      SELECT DISTINCT ON (pi.account_id, pi.crm_product_id)
             pi.account_id, pi.crm_product_id, pi.rate_micros,
             '从历史采购单回填（最近一次采购价）', NOW(), NOW()
        FROM mes_purchase_items pi
        JOIN mes_purchase_orders po ON po.id = pi.purchase_order_id
       WHERE po.approval_status = 'APPROVED'
         AND po.status <> 'CANCELLED'
         AND pi.rate_micros > 0
         AND pi.crm_product_id IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM mes_material_prices mp
                          WHERE mp.account_id = pi.account_id
                            AND mp.crm_product_id = pi.crm_product_id)
       ORDER BY pi.account_id, pi.crm_product_id, po.created_at DESC
    SQL
  end

  def down
    # 只撤回本次这一批（认备注），人工维护过的那些不动。
    execute <<~SQL.squish
      DELETE FROM mes_material_prices
       WHERE updated_by_id IS NULL
         AND remark = '从历史采购单回填（最近一次采购价）'
    SQL
  end
end
