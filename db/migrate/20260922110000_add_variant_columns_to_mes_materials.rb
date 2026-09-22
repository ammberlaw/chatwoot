# 辅助属性（金蝶的「属性组合」）在本系统不另立一层：每个 SKU 就是一条物料，
# 靠 base_no 挂回母件、attrs 记属性值。这样库存/BOM/采购/序列号全都不用改口径，
# 它们原本就按 material_id 走。
#
#   P.07.131      3.7V 电池（母件，base_no 为空）
#   P.07.131_001  base_no=P.07.131  attrs={"电池喷码":"喷码3000"}
#   P.07.131_002  base_no=P.07.131  attrs={"电池喷码":"喷码6000"}
class AddVariantColumnsToMesMaterials < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_materials, :base_no, :string
    add_column :mes_materials, :attrs, :jsonb, null: false, default: {}
    add_index :mes_materials, [:account_id, :base_no],
              name: 'index_mes_materials_on_account_and_base_no'
  end
end
