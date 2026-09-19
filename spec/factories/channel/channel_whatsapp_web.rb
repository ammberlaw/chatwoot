FactoryBot.define do
  # 业务员个人 WhatsApp 号（Baileys 桥），与官方 Cloud API 的 Channel::Whatsapp 相对。
  factory :channel_whatsapp_web, class: 'Channel::WhatsappWeb' do
    sequence(:phone_number) { |n| "+86138000#{n.to_s.rjust(5, '0')}" }
    account
    provider_config { { 'connection_status' => 'connected' } }
  end
end
