json.meta do
  json.revenue_micros @rows.sum { |row| row[:revenue_micros] }
  json.cost_micros @rows.sum { |row| row[:cost_micros] }
  json.margin_micros @rows.sum { |row| row[:margin_micros] }
  json.group_by @summary_by
end
json.payload @rows
json.summary @summary
