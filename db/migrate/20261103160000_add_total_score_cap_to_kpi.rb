class AddTotalScoreCapToKpi < ActiveRecord::Migration[7.1]
  def change
    # 考核表总分上限（分值，不是百分比）。留空 = 不封顶。
    # 与 item_score_cap_pct 一样，方案是模板、考核表是下发时的快照。
    add_column :crm_kpi_schemes, :total_score_cap, :integer
    add_column :crm_kpi_sheets, :total_score_cap, :integer
  end
end
