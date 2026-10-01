json.payload do
  json.array! @inboxes do |inbox|
    json.partial! 'api/v1/models/inbox', formats: [:json], resource: inbox
    # 当前用户是不是这个收件箱的成员（侧栏「我的 WhatsApp」/「业务员 WhatsApp」分组用）。
    json.is_member @member_inbox_ids.include?(inbox.id)
  end
end
