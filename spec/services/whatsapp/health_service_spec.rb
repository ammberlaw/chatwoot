require 'rails_helper'

# health_status 是 Meta 唯一会说出账号级封锁真因的字段：它按 PHONE_NUMBER /
# WABA / BUSINESS / APP 四层各报一次 can_send_message 和错误码。
# 下面的 payload 取自生产 WABA 2026-10-04 的真实响应。
describe Whatsapp::HealthService do
  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:phone_number_id) { whatsapp_channel.provider_config['phone_number_id'] }

  let(:health_status) do
    {
      'can_send_message' => 'BLOCKED',
      'entities' => [
        {
          'entity_type' => 'PHONE_NUMBER',
          'id' => phone_number_id,
          'can_send_message' => 'LIMITED',
          'additional_info' => ['Your display name has not been approved yet.']
        },
        {
          'entity_type' => 'WABA',
          'id' => '1599215615060393',
          'can_send_message' => 'BLOCKED',
          'errors' => [
            {
              'error_code' => 141_008,
              'error_description' => 'The WABA status is not active.',
              'possible_solution' => 'Please contact the WhatsApp support team to activate the account.'
            }
          ]
        },
        { 'entity_type' => 'BUSINESS', 'id' => '2121281901752506', 'can_send_message' => 'AVAILABLE' },
        { 'entity_type' => 'APP', 'id' => '1926785451318399', 'can_send_message' => 'AVAILABLE' }
      ]
    }
  end

  def stub_health_status(body, status: 200)
    stub_request(:get, %r{/#{phone_number_id}\?.*fields=health_status})
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.blocking_summary' do
    it 'names the blocked layer with its error code and official remedy' do
      stub_health_status({ 'health_status' => health_status, 'id' => phone_number_id })

      summary = described_class.blocking_summary(whatsapp_channel)

      expect(summary).to include('WABA 被封锁', 'The WABA status is not active.', '141008', '建议：Please contact')
    end

    it 'also surfaces a merely limited layer so a throttled number is visible' do
      stub_health_status({ 'health_status' => health_status, 'id' => phone_number_id })

      expect(described_class.blocking_summary(whatsapp_channel)).to include('PHONE_NUMBER 受限', 'display name has not been approved')
    end

    it 'skips the layers that are fine' do
      stub_health_status({ 'health_status' => health_status, 'id' => phone_number_id })

      expect(described_class.blocking_summary(whatsapp_channel)).not_to include('BUSINESS', 'APP')
    end

    it 'returns nil when every layer can send' do
      stub_health_status({ 'health_status' => { 'can_send_message' => 'AVAILABLE',
                                                'entities' => [{ 'entity_type' => 'WABA', 'can_send_message' => 'AVAILABLE' }] } })

      expect(described_class.blocking_summary(whatsapp_channel)).to be_nil
    end

    # 诊断绝不能反过来拖垮发消息：出错一律咽掉返回 nil。
    it 'returns nil instead of raising when the API call fails' do
      stub_health_status({ 'error' => { 'message' => 'rate limited' } }, status: 429)

      expect(described_class.blocking_summary(whatsapp_channel)).to be_nil
    end

    it 'returns nil instead of raising when the channel has no token' do
      whatsapp_channel.provider_config = whatsapp_channel.provider_config.merge('api_key' => '')

      expect(described_class.blocking_summary(whatsapp_channel)).to be_nil
    end
  end
end
