class AddMaterialFieldsToMesBomItems < ActiveRecord::Migration[7.1]
  # BOM 用料明细改为照纸质生产任务单直接填（物料编码/名称/规格型号），不再依赖物料库。
  def up
    add_column :mes_bom_items, :material_no, :string
    add_column :mes_bom_items, :material_name, :string
    add_column :mes_bom_items, :specification, :string

    # 存量行从原关联物料回填，避免编辑旧 BOM 时缺名校验失败。
    execute <<~SQL.squish
      UPDATE mes_bom_items bi
      SET material_no = m.material_no,
          material_name = m.name,
          specification = m.specification,
          unit = COALESCE(bi.unit, m.unit)
      FROM mes_materials m
      WHERE bi.mes_material_id = m.id
    SQL
  end

  def down
    remove_column :mes_bom_items, :material_no
    remove_column :mes_bom_items, :material_name
    remove_column :mes_bom_items, :specification
  end
end
