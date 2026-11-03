# 方案模板侧的指标级上限。与 crm_kpi_sheet_items.score_cap_pct 成对——
# 只加考核表那一侧的话，在方案上设了上限、下发时传不过去，等于没设。
class AddScoreCapPctToSchemeItems < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_scheme_items, :score_cap_pct, :integer
  end
end
