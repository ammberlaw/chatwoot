class Whatsapp::HealthService
  # Same relay override as FacebookApiClient — lets the China-hosted server reach GFW-blocked Meta.
  BASE_URI = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com').freeze
  # 发消息失败后顺手做的诊断调用，不能占着 Sidekiq 线程等（上游 relay 还要再转一跳）
  DIAGNOSTIC_TIMEOUT = 8
  ENTITY_STATE_LABELS = { 'BLOCKED' => '被封锁', 'LIMITED' => '受限' }.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  # Meta 对账号级封锁（WABA 被停、未绑支付方式、显示名未审批）在 /messages 上
  # 只回一句「An unknown error has occurred.」，真正的根因只在 health_status 里：
  # 它按 PHONE_NUMBER / WABA / BUSINESS / APP 四层各报一次 can_send_message
  # 和错误码。发送失败路径拿它来把「未知错误」换成人能看懂的原因。
  #
  # 诊断不能反过来拖垮发消息：短超时 + 异常一律咽掉返回 nil。
  def self.blocking_summary(channel)
    new(channel).blocking_summary
  rescue StandardError => e
    Rails.logger.warn "[WHATSAPP HEALTH] blocking_summary failed: #{e.message}"
    nil
  end

  def blocking_summary
    validate_channel!

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{@channel.provider_config['phone_number_id']}",
      query: { fields: 'health_status', access_token: @access_token },
      timeout: DIAGNOSTIC_TIMEOUT
    )
    return nil unless response.success?

    reasons = blocking_reasons(response.parsed_response['health_status'])
    return nil if reasons.blank?

    reasons.join('；')
  end

  def fetch_health_status
    validate_channel!
    fetch_phone_health_data
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      query: {
        fields: health_fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise e
  end

  def health_fields
    %w[
      id
      health_status
      quality_rating
      messaging_limit_tier
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def handle_response(response)
    unless response.success?
      error_message = "WhatsApp API request failed: #{response.code} - #{response.body}"
      Rails.logger.error "[WHATSAPP HEALTH] #{error_message}"
      raise error_message
    end

    data = response.parsed_response
    format_health_response(data)
  end

  def format_health_response(response)
    {
      id: response['id'],
      health_status: response['health_status'],
      blocking_reasons: blocking_reasons(response['health_status']),
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      messaging_limit_tier: response['messaging_limit_tier'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  # health_status 的四层实体里挑出不能发消息的那几层，连错误码和官方给的
  # 处置建议一起摊平成人话。
  #   [{entity_type: 'WABA', can_send_message: 'BLOCKED',
  #     errors: [{error_code: 141008, error_description: '...', possible_solution: '...'}]}]
  # → ["WABA 被封锁：The WABA status is not active.（141008）建议：Please contact..."]
  def blocking_reasons(health_status)
    entities = health_status.is_a?(Hash) ? health_status['entities'] : nil
    return [] if entities.blank?

    entities.filter_map { |entity| entity_blocking_reason(entity) }
  end

  def entity_blocking_reason(entity)
    state = entity['can_send_message']
    return nil if state.blank? || state == 'AVAILABLE'

    label = "#{entity['entity_type']} #{ENTITY_STATE_LABELS.fetch(state, state)}"
    details = Array(entity['errors']).filter_map { |error| format_entity_error(error) }
    details += Array(entity['additional_info'])

    details.present? ? "#{label}：#{details.join(' / ')}" : label
  end

  def format_entity_error(error)
    return nil if error.blank?

    text = error['error_description'].presence || error['error_code']&.to_s
    return nil if text.blank?

    text = "#{text}（#{error['error_code']}）" if error['error_code'].present?
    text = "#{text} 建议：#{error['possible_solution']}" if error['possible_solution'].present?
    text
  end

  def build_expected_webhook_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    return nil if frontend_url.blank?

    "#{frontend_url}/webhooks/whatsapp/#{@channel.phone_number}"
  end
end
