json.meta do
  json.from @report[:from]
  json.to @report[:to]
  json.ytd_from @report[:ytd_from]
  json.totals @report[:totals]
end

json.payload @report[:rows]
