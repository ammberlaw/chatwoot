class Notification::OppoPushService
  def self.client_config
    enabled = ENV['OPPO_PUSH_ENABLED'] == 'true' && %w[OPPO_APP_ID OPPO_APP_KEY OPPO_MASTER_SECRET OPPO_CHANNEL_ID].all? { |key| ENV[key].present? }
    { enabled: enabled, app_id: ENV['OPPO_APP_ID'].to_s }
  end

  def self.authorization
    credentials = [ENV.fetch('OPPO_APP_KEY'), ENV.fetch('OPPO_MASTER_SECRET')]
    Notification::NativePushService.provider_token('oppo', credentials) do
      timestamp = (Time.now.to_f * 1000).to_i.to_s
      result = Notification::NativePushService.request_json('https://api.push.oppomobile.com/server/v1/auth',
                                                            form: { app_key: credentials[0], timestamp: timestamp,
                                                                    sign: Digest::SHA256.hexdigest(credentials[0] + timestamp + credentials[1]) })
      unless result['code'] == 0 && result.dig('data', 'auth_token').present?
        raise Notification::NativePushService::ConfigurationError, 'OPPO authorization failed'
      end

      result.fetch('data').fetch('auth_token')
    end
  end

  def send_message(token:, attributes:, data:)
    alert = Notification::NativePushService.alert_for(data[:kind])
    notification = { app_message_id: Digest::SHA256.hexdigest(data.to_json + token)[0, 32],
                     title: alert[:title], content: alert[:body],
                     click_action_type: 4, click_action_activity: 'com.wintouchspace.app.MainActivity',
                     action_parameters: data.to_json, off_line: true, off_line_ttl: 3600,
                     channel_id: ENV.fetch('OPPO_CHANNEL_ID') }
    result = Notification::NativePushService.request_json('https://api.push.oppomobile.com/server/v1/message/notification/unicast',
                                                         headers: { 'auth_token' => self.class.authorization },
                                                         form: { message: { target_type: 2, target_value: token, notification: notification }.to_json })
    if result['code'] == 10000
      raise Notification::NativePushService::InvalidDeviceError, 'OPPO device registration is no longer valid'
    end
    raise Notification::NativePushService::DeliveryError, "OPPO push failed (#{result['code']})" unless result['code'] == 0

    result.fetch('data')
  end
end
