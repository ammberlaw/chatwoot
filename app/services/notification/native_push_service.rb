require 'httpx'

class Notification::NativePushService
  class ConfigurationError < StandardError; end
  class DeliveryError < StandardError; end
  class InvalidDeviceError < StandardError; end

  PROVIDERS = { apns: 'Notification::ApnsPushService', huawei: 'Notification::HuaweiPushService',
                xiaomi: 'Notification::XiaomiPushService', oppo: 'Notification::OppoPushService',
                vivo: 'Notification::VivoPushService' }.freeze

  # 锁屏文案。按 kind 分——说「新消息」却点开跳到订单详情，看着像推错了。
  # 一律只说「有什么等你处理」，不把单号、客户、金额放锁屏。
  DEFAULT_ALERT = { title: 'WINTOUCH 新消息', body: '你收到一条新消息，打开 App 查看。' }.freeze
  ALERTS = {
    'sales_order_approval' => { title: 'WINTOUCH 待审批提醒', body: '有一张销售订单等你审核，打开 App 查看。' }
  }.freeze

  def self.client_config
    { providers: PROVIDERS.transform_values { |name| name.constantize.client_config } }
  end

  def self.alert_for(kind)
    ALERTS.fetch(kind.to_s, DEFAULT_ALERT)
  end

  def self.http
    HTTPX.with(timeout: { connect_timeout: 5, operation_timeout: 10 })
  end

  def self.request_json(url, **options)
    response = http.post(url, **options)
    raise DeliveryError, 'Official push transport failed' if response.is_a?(HTTPX::ErrorResponse)
    raise DeliveryError, "Official push returned HTTP #{response.status}" unless response.status.between?(200, 299)

    JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    raise DeliveryError, 'Official push returned an invalid response'
  end

  # 两种载荷，对应 App 端 pushMessage 的两条分支：
  # 带 entity_id = 实体类通知（App 按 kind 固定跳 /orders/:id 这类路径，URL 不由后端给）；
  # 带 conversation_id = 会话类通知（点开落进聊天）。
  # rubocop:disable Metrics/ParameterLists -- 载荷构造器，参数摊开比塞进 hash 让人猜键名清楚
  def self.message_data(account_id:, user_id:, kind:, message_id:, conversation_id: nil, entity_id: nil)
    data = { version: '1', kind: kind, account_id: account_id.to_s, user_id: user_id.to_s }
    if entity_id.present?
      data[:entity_id] = entity_id.to_s
    else
      data[:conversation_id] = conversation_id.to_s
    end
    data.merge(message_id: message_id.to_s)
  end
  # rubocop:enable Metrics/ParameterLists

  def self.android_intent(data)
    "intent://messages?#{URI.encode_www_form(data)}#Intent;scheme=wintouchspace;" \
      'package=com.wintouchspace.app;component=com.wintouchspace.app/.MainActivity;end'
  end

  def self.provider_token(provider, credentials)
    key = Digest::SHA256.hexdigest(credentials.join(':'))
    Rails.cache.fetch("official-push:authorization:#{provider}:#{key}", expires_in: 40.minutes) { yield }
  end

  # Recheck ownership after a queued message and send only to this installation.
  def deliver(subscription:, account_id:, user_id:, kind:, message_id:, conversation_id: nil, entity_id: nil)
    attrs = delivery_key = reservation = nil
    subscription.with_lock do
      subscription.reload
      attrs = subscription.subscription_attributes
      provider = subscription.subscription_type.to_sym
      return unless PROVIDERS.key?(provider) && subscription.user_id == user_id && attrs['account_id'].to_i == account_id

      sender = PROVIDERS.fetch(provider).constantize
      config = sender.client_config
      raise ConfigurationError, "Official push is not configured: #{provider}" unless config[:enabled] && config[:app_id] == attrs['app_id']

      if provider == :apns && !config[:environments].include?(attrs['environment'])
        raise ConfigurationError, 'APNs environment is not enabled'
      end

      delivery_key = "native-push:#{kind}:#{message_id}:#{subscription.id}"
      reservation = SecureRandom.uuid
      return unless Redis::Alfred.set(delivery_key, reservation, nx: true, ex: 120)

      data = self.class.message_data(account_id: account_id, user_id: user_id, kind: kind,
                                     conversation_id: conversation_id, entity_id: entity_id,
                                     message_id: message_id)
      result = sender.new.send_message(token: attrs.fetch('push_token'), attributes: attrs, data: data)
      Redis::Alfred.set(delivery_key, 'delivered', ex: 7.days.to_i)
      result
    end
  rescue InvalidDeviceError
    # A late invalid-token response must not delete a newer device registration.
    subscription.with_lock do
      subscription.destroy! if subscription.subscription_attributes['push_token'] == attrs['push_token']
    end
    Redis::Alfred.delete_if_equals(delivery_key, reservation) if reservation
    nil
  rescue ActiveRecord::RecordNotFound
    nil
  rescue StandardError
    Redis::Alfred.delete_if_equals(delivery_key, reservation) if reservation
    raise
  end
end
