# 一条产品线一张核价表（平板 / 商显 / …），各自独立走版本。
# 没有产品线字段时「发布新版归档旧版」会跨产品线互相顶掉。
class AddProductLineToCrmPriceLists < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_price_lists, :product_line, :string
    add_index :crm_price_lists, %i[account_id product_line status],
              name: 'index_crm_price_lists_on_account_line_status'
    # 已有数据（若有）归到一条默认线，避免出现空产品线的表。
    execute("UPDATE crm_price_lists SET product_line = '平板电脑' WHERE product_line IS NULL")
    change_column_null :crm_price_lists, :product_line, false
  end

  def down
    remove_index :crm_price_lists, name: 'index_crm_price_lists_on_account_line_status'
    remove_column :crm_price_lists, :product_line
  end
end
