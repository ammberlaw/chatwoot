class AddCategoryToMesBomItems < ActiveRecord::Migration[7.1]
  def change
    # 用料分类：MACHINE=整机生产物料 / PACKAGING=包装物料。存量默认整机，不影响旧数据。
    add_column :mes_bom_items, :category, :string, null: false, default: 'MACHINE'
  end
end
