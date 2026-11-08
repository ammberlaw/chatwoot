# 每个关键词挖到第几页了。
#
# 之前 Apollo 的分页参数写死 page:1，一个关键词永远只看前 25 条结果——
# 同一个任务重跑十次，搜回来的是同一批公司（2026-11-08 实测：任务4 的 232 家
# 100% 出现在任务5 里）。记住游标之后，每次重跑接着往下挖，才谈得上持续产出。
class AddSearchCursorToCrmLeadCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_lead_campaigns, :search_cursor, :jsonb, null: false, default: {}
  end
end
