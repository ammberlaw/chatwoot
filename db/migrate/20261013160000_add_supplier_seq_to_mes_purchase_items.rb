class AddSupplierSeqToMesPurchaseItems < ActiveRecord::Migration[7.1]
  # 一张采购单里每家供应商一个序号，拼成该供应商专属的采购订单号 PU-20260928-04-01。
  # 供应商交货写这个号、仓库按这个号入库、财务按这个号对账——共用一个 po_no 时三头对不上。
  # 序号一旦发出去就不能变，所以存库而不是渲染时按顺序算（加一家供应商不会把别家的号冲掉）。
  def up
    add_column :mes_purchase_items, :supplier_seq, :integer
    add_index :mes_purchase_items, [:purchase_order_id, :mes_supplier_id, :supplier_seq],
              name: 'index_mes_purchase_items_on_po_supplier_seq'

    # 存量按「该供应商在本单第一行明细的 id」排序编号——与列表里供应商的出现顺序一致。
    execute(<<~SQL.squish)
      UPDATE mes_purchase_items i
         SET supplier_seq = s.seq
        FROM (
          SELECT purchase_order_id,
                 mes_supplier_id,
                 ROW_NUMBER() OVER (PARTITION BY purchase_order_id ORDER BY MIN(id)) AS seq
            FROM mes_purchase_items
           GROUP BY purchase_order_id, mes_supplier_id
        ) s
       WHERE s.purchase_order_id = i.purchase_order_id
         AND s.mes_supplier_id IS NOT DISTINCT FROM i.mes_supplier_id
    SQL
  end

  def down
    remove_index :mes_purchase_items, name: 'index_mes_purchase_items_on_po_supplier_seq'
    remove_column :mes_purchase_items, :supplier_seq
  end
end
