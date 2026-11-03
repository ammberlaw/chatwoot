# 指标级计分上限。留空＝沿用考核表/方案级的 item_score_cap_pct（现有方案不受影响）。
#
# 业务规则（用户 2026-11-03 定）：业绩那一项可以溢出（做到 150% 就该拿 150% 的分），
# 其余各项封顶 100%。原先上限只有方案级一个开关，做不到按项区分——
# 11 月业务方案因此自相矛盾：方案级封 100%，而「业绩目标达成」的标准里写着上限 120%。
class AddScoreCapPctToKpiSheetItems < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_kpi_sheet_items, :score_cap_pct, :integer
  end
end
