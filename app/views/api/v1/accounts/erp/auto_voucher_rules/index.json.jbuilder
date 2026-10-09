json.payload do
  json.array! @rules do |rule|
    json.id rule.id
    json.event_key rule.event_key
    json.name rule.name
    json.is_active rule.is_active
    json.config rule.config
    json.remark rule.remark
    # 这条规则有哪些科目槽位可配（配置界面据此渲染下拉）。
    json.config_slots rule.config_slots
  end
end
