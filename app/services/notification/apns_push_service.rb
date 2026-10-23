class Notification::ApnsPushService
  def self.client_config
    environments = %w[production development].select do |environment|
      prefix = environment == 'development' ? 'APNS_DEVELOPMENT' : 'APNS'
      next false if environment == 'development' && ENV['APNS_DEVELOPMENT_ENABLED'] != 'true'

      path = ENV["#{prefix}_PRIVATE_KEY_PATH"]
      ENV['APNS_ENABLED'] == 'true' && ENV['APNS_TEAM_ID'].present? && ENV["#{prefix}_KEY_ID"].present? &&
        path.present? && File.readable?(path)
    end
    { enabled: environments.any?, app_id: ENV.fetch('APNS_TOPIC', 'com.wintouchspace.app'), environments: environments }
  end

  def self.authorization(environment: 'production')
    @token_mutex ||= Mutex.new
    @token_mutex.synchronize do
      prefix = environment == 'development' ? 'APNS_DEVELOPMENT' : 'APNS'
      path = ENV.fetch("#{prefix}_PRIVATE_KEY_PATH")
      identity = [ENV.fetch("#{prefix}_KEY_ID"), ENV.fetch('APNS_TEAM_ID'), path, File.mtime(path).to_f]
      now = Time.now.to_i
      @provider_tokens ||= {}
      cached = @provider_tokens[environment]
      unless cached && cached[:identity] == identity && now - cached[:issued_at] < 45.minutes.to_i
        key = OpenSSL::PKey.read(File.read(path))
        jwt = JWT.encode({ iss: identity[1], iat: now }, key, 'ES256', kid: identity[0])
        cached = @provider_tokens[environment] = { identity: identity, issued_at: now, token: jwt }
      end
      cached[:token]
    end
  end

  def send_message(token:, attributes:, data:, alert: nil)
    environment = attributes.fetch('environment')
    host = environment == 'development' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
    headers = {
      'authorization' => "bearer #{self.class.authorization(environment: environment)}", 'apns-topic' => self.class.client_config[:app_id],
      'apns-push-type' => 'alert', 'apns-priority' => '10', 'apns-expiration' => (Time.now.to_i + 3600).to_s,
      'apns-collapse-id' => "#{data[:kind]}-#{data[:message_id]}"
    }
    alert ||= Notification::NativePushService.alert_for(data[:kind])
    payload = data.merge(aps: { alert: { title: alert[:title], body: alert[:body] }, sound: 'default' })
    response = Notification::NativePushService.http.with(ssl: { alpn_protocols: ['h2'] }, fallback_protocol: 'h2')
                                              .post("https://#{host}/3/device/#{token}", headers: headers, json: payload)
    raise Notification::NativePushService::DeliveryError, 'APNs transport failed' if response.is_a?(HTTPX::ErrorResponse)
    return response.headers['apns-id'] || 'accepted' if response.status == 200

    reason = JSON.parse(response.body.to_s)['reason']
    if response.status == 410 || %w[BadDeviceToken DeviceTokenNotForTopic].include?(reason)
      raise Notification::NativePushService::InvalidDeviceError, 'APNs device token is no longer valid'
    end
    if response.status == 403
      raise Notification::NativePushService::ConfigurationError, 'APNs provider authorization failed'
    end
    raise Notification::NativePushService::DeliveryError, "APNs returned HTTP #{response.status}"
  rescue JSON::ParserError
    raise Notification::NativePushService::DeliveryError, 'APNs returned an invalid response'
  end
end
