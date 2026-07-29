# 运营类考核方案的平台数据明细表（如商机目标计算/投放效率/三平台询盘明细），
# 结构自由（每表 title+columns+rows），存 JSONB。
class AddDetailTablesToCrmKpiSchemes < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_kpi_schemes, :detail_tables, :jsonb, default: [], null: false
  end
end
