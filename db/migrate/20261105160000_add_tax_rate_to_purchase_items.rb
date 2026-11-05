class AddTaxRateToPurchaseItems < ActiveRecord::Migration[7.1]
  def change
    # 行级税率（百分数，13 表示 13%）。留空＝沿用供应商档案上的税率。
    #
    # 原先税率只能在供应商档案上配，整家一个数。实际同一家供应商不同料的税点可能不同，
    # 也有本来就不开票的单子——2026-11-05 采购反馈「皓显我下单是未税的，怎么还有含税价」，
    # 根因就是档案里配了 5%，而这批货跟对方是不含税结算。
    # 金蝶的采购单是在明细行上直接填税率，这里对齐。
    add_column :mes_purchase_items, :tax_rate, :decimal, precision: 5, scale: 2
  end
end
