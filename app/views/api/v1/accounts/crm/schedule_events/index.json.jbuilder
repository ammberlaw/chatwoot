json.payload do
  json.array! @occurrences do |occ|
    json.partial! 'api/v1/models/crm_schedule_event', formats: [:json], resource: occ[:event]
    # 用「本次发生」的时间覆盖系列基准时间（重复展开后每行是一次具体发生）。
    json.starts_at occ[:starts_at]
    json.ends_at occ[:ends_at]
    json.occurrence_date occ[:starts_at].to_date
    json.done occ[:event].completed_dates.map(&:to_s).include?(occ[:starts_at].to_date.to_s)
  end
end
