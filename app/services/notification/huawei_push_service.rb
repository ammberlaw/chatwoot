class Notification::HuaweiPushService
  def self.client_config
    enabled = ENV['HUAWEI_PUSH_ENABLED'] == 'true' && %w[HUAWEI_APP_ID HUAWEI_CLIENT_ID HUAWEI_CLIENT_SECRET].all? { |key| ENV[key].present? }
    { enabled: enabled, app_id: ENV['HUAWEI_APP_ID'].to_s }
  end

  def self.authorization
    credentials = [ENV.fetch('HUAWEI_CLIENT_ID'), ENV.fetch('HUAWEI_CLIENT_SECRET')]
    Notification::NativePushService.provider_token('huawei', credentials) do
      response = Notification::NativePushService.request_json('https://oauth-login.cloud.huawei.com/oauth2/v3/token',
                                                              form: { grant_type: 'client_credentials', client_id: credentials[0],
                                                                      client_secret: credentials[1] })
      raise Notification::NativePushService::ConfigurationError, 'Huawei authorization failed' unless response['access_token'].present?

      response.fetch('access_token')
    end
  end

  def send_message(token:, attributes:, data:, alert: nil)
    alert ||= Notification::NativePushService.alert_for(data[:kind])
    payload = { message: { token: [token], data: data.to_json,
                          notification: { title: alert[:title], body: alert[:body] },
                          android: { ttl: '3600s', category: 'IM',
                                     notification: { channel_id: 'wintouch-messages',
                                                     click_action: { type: 1, intent: Notification::NativePushService.android_intent(data) } } } } }
    result = Notification::NativePushService.request_json(
      "https://push-api.cloud.huawei.com/v1/#{ENV.fetch('HUAWEI_CLIENT_ID')}/messages:send",
      headers: { 'Authorization' => "Bearer #{self.class.authorization}" }, json: payload
    )
    raise Notification::NativePushService::DeliveryError, "Huawei push failed (#{result['code']})" unless result['code'].to_s == '80000000'

    result.fetch('requestId')
  end
end
