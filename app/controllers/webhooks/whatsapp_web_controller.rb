class Webhooks::WhatsappWebController < ActionController::API
  before_action :authenticate_bridge

  # Inbound message forwarded by the Baileys bridge.
  def process_payload
    # from_me：业务员在手机上直接回的消息，落成「我方发出」（见 IncomingMessageWhatsappWebService）。
    payload = params.to_unsafe_hash.slice(:inbox_id, :source_id, :phone, :from, :name, :text, :message_id, :timestamp, :from_me)
    Webhooks::WhatsappWebEventsJob.perform_later(payload)
    head :ok
  end

  # 配对时 WhatsApp 推来的历史消息，桥按批转发（一批几百条）。
  # 筛选与落库都在后台任务里做，这里只接下来立刻返回，别把桥卡住。
  def history
    Webhooks::WhatsappWebHistoryJob.perform_later(
      'inbox_id' => params[:inbox_id],
      'messages' => Array(params[:messages]).map { |m| m.permit!.to_h }
    )
    head :ok
  end

  # Delivery/read receipt for an outgoing message, reported by the bridge.
  # Advances status forward only (sent → delivered → read); never downgrades.
  def receipt
    inbox = Inbox.find_by(id: params[:inbox_id])
    return head :not_found unless inbox&.channel_type == 'Channel::WhatsappWeb'

    message = inbox.messages.find_by(source_id: params[:message_id])
    return head :not_found unless message

    rank = { 'sent' => 0, 'delivered' => 1, 'read' => 2 }
    incoming = rank[params[:status].to_s]
    message.update!(status: params[:status]) if incoming && incoming > rank.fetch(message.status, -1)
    head :ok
  end

  # Connection state change (open/close/qr) reported by the bridge.
  def status
    channel = find_channel
    return head :not_found unless channel

    updates = { connection_status: params[:status] }
    updates[:phone_number] = params[:phone_number] if params[:phone_number].present?
    channel.update!(updates)
    head :ok
  end

  private

  def authenticate_bridge
    token = request.headers['X-Bridge-Token']
    expected = ENV.fetch('WHATSAPP_BRIDGE_TOKEN', nil)
    head :unauthorized if expected.blank? || token != expected
  end

  def find_channel
    inbox = Inbox.find_by(id: params[:inbox_id])
    inbox&.channel_type == 'Channel::WhatsappWeb' ? inbox.channel : nil
  end
end
