# == Schema Information
#
# Table name: channel_whatsapp_web
#
#  id              :bigint           not null, primary key
#  phone_number    :string
#  provider_config :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :integer          not null
#
# Indexes
#
#  index_channel_whatsapp_web_on_account_id    (account_id)
#  index_channel_whatsapp_web_on_phone_number  (phone_number) UNIQUE WHERE (phone_number IS NOT NULL)
#

# Personal WhatsApp number connected via the WhatsApp Web protocol (Baileys bridge),
# as opposed to Channel::Whatsapp which is the official Cloud API / 360Dialog.
class Channel::WhatsappWeb < ApplicationRecord
  include Channelable

  self.table_name = 'channel_whatsapp_web'
  EDITABLE_ATTRS = [:phone_number, { provider_config: {} }].freeze

  validates :phone_number, uniqueness: true, allow_nil: true

  # disconnected_at：掉线那一刻的时间戳（ISO8601 字符串）。连上时清空。
  # 给 Crm::WhatsappWebHealthJob 算「掉了几天」用——不记的话只知道现在是断的，
  # 不知道是刚断还是断了一个月，而这两件事该做的处理完全不同。
  store_accessor :provider_config, :connection_status, :disconnected_at

  def name
    'WhatsApp Web'
  end

  # Bridge sessions are keyed by inbox id; the inbox always exists once the channel is created.
  def session_key
    inbox&.id
  end
end
