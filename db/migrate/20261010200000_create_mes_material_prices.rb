# 物料单价表：财务/采购维护的标准价，给成本核算兜底。
#
# 为什么要这张表：生产任务单算单台成本时要给每颗料配价，但采购单只覆盖已经下过单的料
# （2026-10-10 实测 281 个料号里只有 79 个有价，其余只存在金蝶里）。有了这张表，
# 财务把现有单价表 Excel 贴进来就补齐了，不用等采购把所有单补录一遍。
#
# 按商品档（crm_products）挂：生产端把屏、主板这些料都建在商品档里，
# 生产任务单用料行的「代码」就是商品档的 sku（实测 393 行 100% 对得上）。
class CreateMesMaterialPrices < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_material_prices do |t|
      t.references :account, null: false, foreign_key: true
      t.references :crm_product, null: false, foreign_key: { to_table: :crm_products, on_delete: :cascade }
      t.bigint :unit_price_micros, null: false, default: 0
      t.text :remark
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end

    add_index :mes_material_prices, [:account_id, :crm_product_id], unique: true,
                                                                    name: 'idx_mes_material_prices_on_account_product'
  end
end
