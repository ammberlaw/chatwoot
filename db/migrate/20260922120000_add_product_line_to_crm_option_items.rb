# 产品分组树（crm_option_items 里 category=product_group）原本是全账号共用的，
# 没有产线字段——结果产线切到「平板」，看到的还是商显那棵树（显示器/触摸屏/电容触摸屏）。
#
# 加一列产线：null = 公共分组（各产线都能看到），有值 = 只属于该产线。
# 其余 category（客户分组/客户来源）不参与产线分流，这列对它们始终为 null。
class AddProductLineToCrmOptionItems < ActiveRecord::Migration[7.1]
  def up
    add_column :crm_option_items, :product_line, :string
    add_index :crm_option_items, [:account_id, :category, :product_line],
              name: 'idx_crm_option_items_line'

    # 存量产品分组都是商显时期建的（显示器/触摸屏/电容触摸屏），回填到商显产线；
    # 不回填的话它们会变成「公共分组」，平板那边照样串味。
    execute <<~SQL.squish
      UPDATE crm_option_items
         SET product_line = 'COMMERCIAL_DISPLAY'
       WHERE category = 'product_group'
    SQL
  end

  def down
    remove_index :crm_option_items, name: 'idx_crm_option_items_line'
    remove_column :crm_option_items, :product_line
  end
end
