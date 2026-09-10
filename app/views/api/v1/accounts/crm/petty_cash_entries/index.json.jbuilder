json.meta do
  json.opening @opening
  json.book_id @book.id
  json.book_name @book.name
end

json.payload do
  json.array! @entries do |entry|
    json.partial! 'api/v1/models/crm_petty_cash_entry', formats: [:json], resource: entry
  end
end
