json.meta do
  # 合计按全量订单算（不是明细截断后的 200 行）——截断的合计是错数。
  json.revenue_micros @totals[:revenue_micros]
  json.cost_micros @totals[:cost_micros]
  json.margin_micros @totals[:margin_micros]
  json.group_by @summary_by
  json.truncated @truncated
  json.total_count @total_count
  # 业务员下拉名单（只含真有订单的人）。中文名优先——财务板块只给自己人看。
  json.owners @owners do |user|
    json.id user.id
    json.name user.name.presence || user.crm_name
  end
end
json.payload @rows
json.summary @summary
# 按最近一次采购单价计价时查不到价、因而按 0 计入成本的料。
json.unpriced do
  json.count @unpriced[:count]
  json.rows @unpriced[:rows]
end
