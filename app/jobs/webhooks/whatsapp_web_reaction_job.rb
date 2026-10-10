class Webhooks::WhatsappWebReactionJob < ApplicationJob
  queue_as :default

  def perform(params)
    inbox = Inbox.find_by(id: params[:inbox_id])
    return unless inbox&.channel_type == 'Channel::WhatsappWeb'

    Whatsapp::IncomingReactionWhatsappWebService.new(inbox: inbox, params: params).perform
  end
end
