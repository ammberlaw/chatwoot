class Notification::VivoPushService
  def self.client_config
    enabled = ENV['VIVO_PUSH_ENABLED'] == 'true' && %w[VIVO_APP_ID VIVO_APP_KEY VIVO_APP_SECRET].all? { |key| ENV[key].present? }
    { enabled: enabled, app_id: ENV['VIVO_APP_ID'].to_s }
  end

  def self.authorization
    credentials = [ENV.fetch('VIVO_APP_ID'), ENV.fetch('VIVO_APP_KEY'), ENV.fetch('VIVO_APP_SECRET')]
    Notification::NativePushService.provider_token('vivo', credentials) do
      timestamp = (Time.now.to_f * 1000).to_i
      signature = Digest::MD5.hexdigest(credentials[0] + credentials[1] + timestamp.to_s + credentials[2])
      result = Notification::NativePushService.request_json('https://api-push.vivo.com.cn/message/auth',
                                                           json: { appId: credentials[0].to_i, appKey: credentials[1], timestamp: timestamp,
                                                                   sign: signature })
      unless result['result'] == 0 && result['authToken'].present?
        raise Notification::NativePushService::ConfigurationError, 'vivo authorization failed'
      end

      result.fetch('authToken')
    end
  end

  def send_message(token:, attributes:, data:)
    alert = Notification::NativePushService.alert_for(data[:kind])
    payload = { appId: ENV.fetch('VIVO_APP_ID').to_i, regId: token, notifyType: 4, category: 'IM',
                title: alert[:title], content: alert[:body], timeToLive: 3600,
                skipType: 4, skipContent: Notification::NativePushService.android_intent(data),
                clientCustomMap: data, requestId: Digest::SHA256.hexdigest(data.to_json + token)[0, 32] }
    result = Notification::NativePushService.request_json('https://api-push.vivo.com.cn/message/send',
                                                         headers: { 'authToken' => self.class.authorization }, json: payload)
    if result['result'] == 10302 && [1, 2].include?(result.dig('invalidUser', 'status'))
      raise Notification::NativePushService::InvalidDeviceError, 'vivo device registration is no longer valid'
    end
    raise Notification::NativePushService::DeliveryError, "vivo push failed (#{result['result']})" unless result['result'] == 0

    result.fetch('taskId')
  end
end
