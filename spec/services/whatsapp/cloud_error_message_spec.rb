require 'rails_helper'

describe Whatsapp::CloudErrorMessage do
  subject(:error_message) { described_class.call(response, whatsapp_channel) }

  let(:whatsapp_channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }

  let(:response) { instance_double(HTTParty::Response, body: body.to_json, parsed_response: body, code: 400) }

  before do
    allow(Rails.logger).to receive(:error)
  end

  context 'when Meta reports a concrete error' do
    let(:body) { { 'error' => { 'message' => 'Invalid parameter', 'code' => 100 } } }

    it 'keeps the message and appends the error code' do
      expect(error_message).to eq('Invalid parameter (100)')
    end

    it 'does not spend an extra API call on health_status' do
      expect(Whatsapp::HealthService).not_to receive(:blocking_summary)
      error_message
    end
  end

  context 'when Meta provides a subcode' do
    let(:body) { { 'error' => { 'message' => 'Template paused', 'code' => 132_015, 'error_subcode' => 2_494_010 } } }

    it 'reports both codes' do
      expect(error_message).to eq('Template paused (132015/2494010)')
    end
  end

  # Meta 把人话写在三个地方，取对发件人最有解释力的那个。
  context 'when Meta provides a user-facing message' do
    let(:body) do
      {
        'error' => {
          'message' => 'Generic error',
          'error_user_msg' => '收件人号码不在 WhatsApp 上',
          'error_data' => { 'details' => 'recipient not found' },
          'code' => 131_026
        }
      }
    end

    it 'prefers error_user_msg over message and details' do
      expect(error_message).to eq('收件人号码不在 WhatsApp 上 (131026)')
    end
  end

  context 'when only error_data.details carries the explanation' do
    let(:body) do
      {
        'error' => {
          'message' => 'Generic error',
          'error_data' => { 'details' => 'Message failed to send because more than 24 hours have passed' },
          'code' => 131_047
        }
      }
    end

    it 'falls back to details' do
      expect(error_message).to eq('Message failed to send because more than 24 hours have passed (131047)')
    end
  end

  # 账号级封锁（WABA 被停、未绑支付方式）时 Meta 只回这一句，真因只在 health_status 里。
  context 'when Meta returns an uninformative unknown error' do
    let(:body) { { 'error' => { 'message' => 'An unknown error has occurred.', 'code' => 1 } } }

    before do
      allow(Whatsapp::HealthService).to receive(:blocking_summary)
        .and_return('WABA 被封锁：The WABA status is not active.（141008）')
    end

    it 'appends the root cause looked up from health_status' do
      expect(error_message).to eq('An unknown error has occurred. · WABA 被封锁：The WABA status is not active.（141008） (1)')
    end
  end

  context 'when the health_status lookup itself yields nothing' do
    let(:body) { { 'error' => { 'message' => 'An unknown error has occurred.', 'code' => 1 } } }

    before do
      allow(Whatsapp::HealthService).to receive(:blocking_summary).and_return(nil)
    end

    it 'still returns what Meta said' do
      expect(error_message).to eq('An unknown error has occurred. (1)')
    end
  end

  # relay 挂了 / 网关 502 / HTML 错误页：至少把状态码留下，别让消息悄悄停在「发送中」。
  context 'when the response carries no error object' do
    let(:response) { instance_double(HTTParty::Response, body: '<html>502 Bad Gateway</html>', parsed_response: nil, code: 502) }

    it 'falls back to the HTTP status and body' do
      expect(error_message).to include('HTTP 502').and include('502 Bad Gateway')
    end
  end
end
