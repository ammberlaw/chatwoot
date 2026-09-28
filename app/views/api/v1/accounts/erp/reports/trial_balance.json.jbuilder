json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.totals @report[:totals]
  json.checks @report[:checks]
  json.balanced @report[:balanced]
end

json.payload @report[:rows]
