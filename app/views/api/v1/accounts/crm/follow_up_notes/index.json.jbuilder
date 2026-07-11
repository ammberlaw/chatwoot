json.meta do
  json.count @notes_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @notes do |note|
    json.partial! 'api/v1/models/crm_follow_up_note', formats: [:json], resource: note
  end
end
