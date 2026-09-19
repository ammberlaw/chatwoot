# frozen_string_literal: true

FactoryBot.define do
  factory :inbox do
    account
    channel { FactoryBot.build(:channel_widget, account: account) }
    name { 'Inbox' }

    after(:create) do |inbox|
      inbox.channel.save!
    end

    trait :with_email do
      channel { FactoryBot.build(:channel_email, account: account) }
      name { 'Email Inbox' }
    end

    # 业务员绑的个人 WhatsApp 号：一号一箱、只有本人是成员，本人看得见整箱
    # （公共收件箱只看分给自己的，见 Conversations::Visibility）。
    trait :personal_whatsapp do
      channel { FactoryBot.build(:channel_whatsapp_web, account: account) }
      name { 'Personal WhatsApp' }
    end
  end
end
