json.may_edit_company @may_edit_company
json.company @company do |row|
  json.(row, :id, :content)
  json.created_at row.created_at
end
json.mine @mine do |row|
  json.(row, :id, :content)
  json.created_at row.created_at
end
