class Notification::XiaomiPushService
  def self.client_config
    enabled = ENV['XIAOMI_PUSH_ENABLED'] == 'true' && %w[XIAOMI_APP_ID XIAOMI_APP_SECRET XIAOMI_CHANNEL_ID].all? { |key| ENV[key].present? }
    { enabled: enabled, app_id: ENV['XIAOMI_APP_ID'].to_s }
  end

  def send_message(token:, attributes:, data:, alert: nil)
    alert ||= Notification::NativePushService.alert_for(data[:kind])
    form = { registration_id: token, restricted_package_name: 'com.wintouchspace.app',
             title: alert[:title], description: alert[:body], payload: data.to_json,
             time_to_live: 3_600_000, notify_type: -1, 'extra.notify_effect' => '2',
             'extra.intent_uri' => Notification::NativePushService.android_intent(data),
             'extra.channel_id' => ENV.fetch('XIAOMI_CHANNEL_ID'),
             'extra.jobkey' => Digest::SHA256.hexdigest(data.to_json + token)[0, 20] }
    result = Notification::NativePushService.request_json('https://api.xmpush.xiaomi.com/v3/message/regid',
                                                         headers: { 'Authorization' => "key=#{ENV.fetch('XIAOMI_APP_SECRET')}" }, form: form)
    unless result['code'] == 0 && result['result'] == 'ok'
      raise Notification::NativePushService::DeliveryError, "Xiaomi push failed (#{result['code']})"
    end

    result.fetch('data').fetch('id')
  end
end
