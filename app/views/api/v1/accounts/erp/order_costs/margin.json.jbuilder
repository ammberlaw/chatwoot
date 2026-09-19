json.meta do
  # 合计按全量订单算（不是明细截断后的 200 行）——截断的合计是错数。
  json.revenue_micros @totals[:revenue_micros]
  json.cost_micros @totals[:cost_micros]
  json.margin_micros @totals[:margin_micros]
  json.group_by @summary_by
  json.truncated @truncated
  json.total_count @total_count
end
json.payload @rows
json.summary @summary
