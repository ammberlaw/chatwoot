json.meta do
  json.as_of @aging[:as_of]
  json.basis @aging[:basis]
  json.buckets @aging[:buckets]
  json.totals @aging[:totals]
end

json.payload @aging[:rows]
