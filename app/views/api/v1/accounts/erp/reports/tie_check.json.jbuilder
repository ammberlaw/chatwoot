json.meta do
  json.as_of @report[:as_of]
  json.passed @report[:checks].all? { |check| check[:passed] }
  json.failed_count @report[:checks].count { |check| !check[:passed] }
end

json.payload @report[:checks]
