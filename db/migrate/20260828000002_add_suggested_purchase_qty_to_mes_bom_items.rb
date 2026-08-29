class AddSuggestedPurchaseQtyToMesBomItems < ActiveRecord::Migration[7.1]
  def change
    # 工程建议采购数量：工程在 BOM 用料明细上按经验/安全库存给出的采购建议量，
    # 供采购按 BOM 算料时参考（与本单实际需求量、实时库存并列展示）。
    add_column :mes_bom_items, :suggested_purchase_qty, :decimal, precision: 14, scale: 3
  end
end
