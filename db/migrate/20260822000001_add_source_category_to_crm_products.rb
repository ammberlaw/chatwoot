class AddSourceCategoryToCrmProducts < ActiveRecord::Migration[7.1]
  # 商品类别（来源分类）：承接金蝶等外部商品主档的中文类别（背包屏 / 商显主板 …），
  # 与内置固定五档 category（仓别：成品仓/半成品仓/主料/辅料/不良品仓）并存互不干扰。
  def change
    add_column :crm_products, :source_category, :string
    add_index :crm_products, %i[account_id source_category],
              name: 'index_crm_products_on_account_and_source_category'
  end
end
