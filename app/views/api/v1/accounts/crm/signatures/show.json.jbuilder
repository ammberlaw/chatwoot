json.exists @signature.persisted? && @signature.image.attached?
json.image_url @signature.image.attached? ? url_for(@signature.image) : nil
json.updated_at @signature.updated_at
