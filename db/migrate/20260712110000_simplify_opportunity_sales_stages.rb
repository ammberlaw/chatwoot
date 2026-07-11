class SimplifyOpportunitySalesStages < ActiveRecord::Migration[7.1]
  # 商机阶段精简为 4 项：需求确认(已报价) / 样品中 / 已成交 / 输单。
  # 存量数据重映射：初步接触·已报价 → 需求确认；谈判中 → 样品中。
  def up
    execute <<~SQL.squish
      UPDATE crm_opportunities SET sales_stage = 'NEEDS_CONFIRMED'
      WHERE sales_stage IN ('INITIAL_CONTACT', 'QUOTED')
    SQL
    execute <<~SQL.squish
      UPDATE crm_opportunities SET sales_stage = 'SAMPLING'
      WHERE sales_stage = 'NEGOTIATING'
    SQL
    change_column_default :crm_opportunities, :sales_stage, from: 'INITIAL_CONTACT', to: 'NEEDS_CONFIRMED'
  end

  def down
    change_column_default :crm_opportunities, :sales_stage, from: 'NEEDS_CONFIRMED', to: 'INITIAL_CONTACT'
  end
end
