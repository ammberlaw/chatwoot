# 存货科目映射：产品档案的「来源类别」→ 存货科目（原材料 1403 / 库存商品 1405 / 委托加工物资 1408）。
# 采购入库凭证按这张表决定借方科目（财务 2026-10-06 拍板，见 ERP_SPEC §8.2bis）。
#
# 为什么不写死「来源类别 == '成品'」：生产上 4887 个产品有 232 种来源类别，
# 光"成品"就散成 成品 / 10.1寸成品 / 7寸成品 / 外购机（含客供主板）/ 裸机 等 24 种写法，
# 写死会把一百多个带尺寸的成品和全部外购机错记成原材料。
class AddInventoryAccountMapToErpSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :erp_settings, :inventory_account_map, :jsonb, default: {}, null: false
  end
end
