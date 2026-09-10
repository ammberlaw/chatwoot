json.id resource.id
json.title resource.title
json.product_line resource.product_line
json.effective_on resource.effective_on
json.currency resource.currency
json.status resource.status
json.status_label resource.status_label
json.columns resource.column_defs
json.header_note resource.header_note
json.rules_note resource.rules_note
json.footer_name resource.footer_name
json.item_count resource.items.size
json.has_images resource.items.any? { |i| i.image.attached? }
json.creator_name resource.creator&.crm_display_name
json.published_by_name resource.published_by&.crm_display_name
json.published_at resource.published_at
json.updated_at resource.updated_at
if defined?(with_items) && with_items
  json.items resource.items.ordered do |item|
    json.id item.id
    json.values item.values
    json.remark item.remark
    json.image_url item.image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(item.image, only_path: true) : nil
  end
end
