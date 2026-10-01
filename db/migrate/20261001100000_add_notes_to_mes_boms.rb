class AddNotesToMesBoms < ActiveRecord::Migration[7.1]
  def change
    # purchase_note 采购注意事项：PMC 写给采购看的（指定品牌/替代料/到货节点等），
    # 建采购单时自动带过去，但导出给供应商的文件里不出现。
    # production_note 生产备注：只给公司内部生产部门看，不进任何对外文件。
    add_column :mes_boms, :purchase_note, :text
    add_column :mes_boms, :production_note, :text
  end
end
