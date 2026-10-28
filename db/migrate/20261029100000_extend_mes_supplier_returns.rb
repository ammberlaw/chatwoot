# 采购退料（原「退料返修」）扩成真正的单据：带价格、关联单号、从哪个仓退，并且真的动库存。
#
# 原来它只是一本台账——记「退出去多久回来」，一行料只有数量，既没有价格也不扣库存。
# 用户 2026-10-29 要的是：单号/供应商/物料编码/名称/规格/数量/价格/单位/关联单号（入库单+采购单）/库存，
# 还要能打印，并且「从不良品仓退回供应商」——最后这句意味着它必须真扣库存。
#
# return_kind 是财务口径的分叉，用户定的两种：
#   REPLACE 退回去换新的 → 只扣不良品仓的库存，采购单到货量和应付都不动（钱照付，货会回来）
#   REFUND  退掉不要了   → 连采购到货量和应付红字一起冲
# 实现上不新建 purpose：过账生成的 PURCHASE_RETURN 库存单带不带 purchase_order_id，
# 恰好就是这两种——Mes::StockEntry#apply_purchase_receipt 和
# Erp::AutoVoucherService#stock_receipt_rows 都只在有采购单时才动采购/应付。
class ExtendMesSupplierReturns < ActiveRecord::Migration[7.1]
  def change
    change_table :mes_supplier_returns, bulk: true do |t|
      t.string :return_kind, null: false, default: 'REPLACE'
      # 从哪个仓退出去。默认不良品仓——退给供应商的货基本都先进了那儿。
      t.bigint :warehouse_id
      # 关联采购单：REFUND 靠它冲到货量和应付；REPLACE 也可以挂着只为对账。
      t.bigint :mes_purchase_order_id
      # 货是哪张入库单收进来的。用户点名要的「关联单号」之一。
      t.bigint :source_stock_entry_id
      # 过账时生成的那张 PURCHASE_RETURN 出库单。
      t.bigint :out_stock_entry_id
      t.datetime :posted_at
    end

    add_index :mes_supplier_returns, [:account_id, :return_kind]
    add_index :mes_supplier_returns, :mes_purchase_order_id

    # 价格：默认从关联采购单上那颗料的单价带出来，也允许手改（退货价和采购价不一定一样）。
    add_column :mes_supplier_return_items, :unit_price_micros, :bigint, null: false, default: 0
  end
end
