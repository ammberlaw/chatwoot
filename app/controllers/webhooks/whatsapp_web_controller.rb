class Webhooks::WhatsappWebController < ActionController::API
  before_action :authenticate_bridge

  # 入站媒体上限。桥那边也卡了 64MB；这里再卡一道，别让畸形请求把内存撑爆。
  MEDIA_MAX_BYTES = 64.megabytes

  # Inbound message forwarded by the Baileys bridge.
  def process_payload
    # from_me：业务员在手机上直接回的消息，落成「我方发出」（见 IncomingMessageWhatsappWebService）。
    payload = params.to_unsafe_hash.slice(:inbox_id, :source_id, :phone, :from, :name, :book_name, :text, :message_id, :timestamp,
                                          :from_me, :quoted_id)
    # 图片/视频/语音/文件走 multipart 上来。文件对象进不了 ActiveJob（序列化不了），
    # 所以在这里先落成 blob，只把 signed_id 带进后台任务。
    payload[:media_signed_id] = stage_media&.signed_id
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

  # 桥推来的联系人资料：手机通讯录里的备注名（name）+ 对方自设的 WhatsApp 昵称（notify）。
  # 业务员在手机上给客户改了备注，这里把它同步成 CRM 联系人名。筛选与覆盖规则在
  # Whatsapp::WebContactSync 里（人工在 CRM 改过的名字不动）。
  def contacts
    Webhooks::WhatsappWebContactsJob.perform_later(
      'inbox_id' => params[:inbox_id],
      'contacts' => Array(params[:contacts]).map { |c| c.permit(:source_id, :id, :lid, :phone, :name, :notify).to_h }
    )
    head :ok
  end

  # 联系人头像。头像在 pps.whatsapp.net 上、生产机连不通那个域，所以由香港桥下载完
  # 把字节 multipart 传过来，这边只落盘（见 Whatsapp::WebAvatarSync）。
  def avatar
    inbox = Inbox.find_by(id: params[:inbox_id])
    return head :not_found unless inbox&.channel_type == 'Channel::WhatsappWeb'

    file = params[:avatar]
    return head :bad_request unless file.respond_to?(:tempfile)

    result = Whatsapp::WebAvatarSync.new(
      inbox: inbox,
      entry: params.permit(:source_id, :id, :lid, :phone, :img_hash).to_h.with_indifferent_access,
      file: file
    ).perform
    render json: { result: result }
  rescue StandardError => e
    Rails.logger.error("[wa_avatar] 落盘失败 inbox=#{params[:inbox_id]}: #{e.class} #{e.message}")
    head :internal_server_error
  end

  # 表情回应。不是一条新消息，而是挂到被回应的那条上，所以单走一个端点
  # （走 process_payload 会被当成空消息丢掉）。emoji 为空表示客户撤销了回应。
  def reaction
    payload = params.to_unsafe_hash.slice(:inbox_id, :target_id, :emoji, :from_me, :source_id, :timestamp)
    Webhooks::WhatsappWebReactionJob.perform_later(payload)
    head :ok
  end

  # 某条消息被撤回了。两种来源：客户在他手机上撤回了自己发的，或者业务员在自己手机上
  # 撤回了我们发的（从 CRM 撤的那条已经在 SendRevokeService 里落过库，这里按 revoked 判重）。
  # 原文一并清掉——和手机上一样，撤回了就谁都看不到。
  def revoke
    message = find_web_message
    return head :not_found unless message

    Messages::RevokeService.new(
      message: message,
      by: params[:from_me].to_s == 'true' ? Messages::RevokeService::AGENT : Messages::RevokeService::CONTACT
    ).perform
    head :ok
  end

  # 某条消息被编辑了（客户改了他那条，或业务员在手机上改了我们那条）。
  # 正文换成新内容、挂上「已编辑」，和手机上看到的保持一致。
  def edit
    message = find_web_message
    return head :not_found unless message
    # 撤回过的不再跟着改：WhatsApp 不会对已撤回的消息发编辑，真来了也该当脏数据丢掉。
    return head :ok if message.content_attributes['revoked'] || params[:text].blank?

    Messages::EditService.new(message: message, content: params[:text]).perform
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

  # 撤回/编辑都是按「那条消息在 WhatsApp 上的 id」找本地那条。找不到说明这条从没进过 CRM
  # （配对前的老消息、群聊、被过滤掉的媒体），没什么可做的。
  def find_web_message
    inbox = Inbox.find_by(id: params[:inbox_id])
    return nil unless inbox&.channel_type == 'Channel::WhatsappWeb'

    inbox.messages.find_by(source_id: params[:message_id])
  end

  # 把上传的媒体存成 ActiveStorage blob。超限或空文件直接丢弃媒体（消息本身照落，
  # 至少留下「客户此刻发过东西」这条记录），不让整条 webhook 失败。
  def stage_media
    file = params[:media]
    return nil unless file.respond_to?(:tempfile)

    size = file.size.to_i
    if size.zero? || size > MEDIA_MAX_BYTES
      Rails.logger.warn("[whatsapp_web] 丢弃入站媒体：size=#{size} inbox=#{params[:inbox_id]}")
      return nil
    end

    ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile,
      filename: file.original_filename.presence || 'whatsapp-media',
      content_type: file.content_type.presence || 'application/octet-stream'
    )
  rescue StandardError => e
    Rails.logger.error("[whatsapp_web] 入站媒体落盘失败：#{e.class} #{e.message}")
    nil
  end

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
