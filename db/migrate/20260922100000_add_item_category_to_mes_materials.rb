# 金蝶商品档案里的「商品类别」（包材/主板/外壳/皮套…共 22 类）是采购品类，
# 与本表已有的 category（仓别：原料/半成品/成品/耗材）是两个维度，不能并成一个字段——
# 库存按 category 走，塞中文品类会把仓别逻辑搞乱。故另立一列原样保留品类。
class AddItemCategoryToMesMaterials < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_materials, :item_category, :string
    add_index :mes_materials, [:account_id, :item_category],
              name: 'index_mes_materials_on_account_and_item_category'
  end
end
