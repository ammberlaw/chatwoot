class Webhooks::WhatsappWebEventsJob < ApplicationJob
  queue_as :default

  def perform(params)
    inbox = Inbox.find_by(id: params[:inbox_id])
    return unless inbox&.channel_type == 'Channel::WhatsappWeb'

    Whatsapp::IncomingMessageWhatsappWebService.new(inbox: inbox, params: params).perform
  end
end
