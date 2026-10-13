# Thin HTTP client for the wintouch-wa-bridge (Baileys) service.
# Sessions are keyed by Chatwoot inbox id.
class Whatsapp::BaileysBridgeClient
  class BridgeError < StandardError; end

  def connect(inbox_id)
    post("/sessions/#{inbox_id}/connect")
  end

  def status(inbox_id)
    get("/sessions/#{inbox_id}/status")
  end

  # 全部会话的实时状态：{ "<session_key>" => "open" | ... }。
  # 「我的 WhatsApp」列表一次问全部，不用逐个号发请求（12 个号就是 12 次跨境往返）。
  # 桥接不可达时返回 {}，调用方按「拿不到实况」处理，不把界面写成全掉线。
  def sessions_status
    body = get('/sessions')
    body.is_a?(Hash) ? body['sessions'].to_h : {}
  rescue BridgeError, StandardError
    {}
  end

  def logout(inbox_id)
    post("/sessions/#{inbox_id}/logout")
  end

  # quoted 非空时发成「引用回复」（桥接用它搭 Baileys 的 quoted 存根）；为空则是普通消息。
  def send_text(inbox_id, phone, text, quoted: nil)
    payload = { phone: phone, text: text }
    payload[:quoted] = quoted if quoted.present?
    body = post("/sessions/#{inbox_id}/send", payload)
    body['message_id']
  end

  # 发附件：把附件的公开链接交给桥接，由它取回字节再经 Baileys 发出去
  # （几 MB 的 PI/图纸走 base64 会把请求体撑得很难看）。
  def send_media(inbox_id, phone, media)
    payload = media.slice(:url, :filename, :mimetype, :caption, :quoted).compact.merge(phone: phone)
    body = post("/sessions/#{inbox_id}/send-media", payload)
    body['message_id']
  end

  # 表情回应。emoji 传空字符串 = 撤销（Baileys 和 WhatsApp 都用空串表达撤销）。
  # target_id 是被回应那条的 WhatsApp 消息 id，from_me 决定桥那边怎么拼 key——
  # 拼错了对方客户端不认这条回应，界面上什么都不会出现。
  def send_reaction(inbox_id, phone, target_id:, from_me:, emoji:)
    post("/sessions/#{inbox_id}/reaction",
         { phone: phone, target_id: target_id, from_me: from_me, emoji: emoji.to_s })
  end

  # 撤回（WhatsApp 的「为所有人删除」）。target_id 是那条消息在 WhatsApp 上的 id；
  # 只撤自己发的，所以桥那侧的 key 恒按 fromMe 拼。
  def revoke_message(inbox_id, phone, target_id:)
    post("/sessions/#{inbox_id}/revoke", { phone: phone, target_id: target_id })
  end

  # 编辑已发出的消息。只对纯文字消息有意义，超过 WhatsApp 的 15 分钟窗口对方客户端会忽略
  # （窗口在 Messages::SendEditService 里先卡掉，这里不重复判）。
  def edit_message(inbox_id, phone, target_id:, text:)
    post("/sessions/#{inbox_id}/edit", { phone: phone, target_id: target_id, text: text })
  end

  # 号码是否注册了 WhatsApp。发起新会话前先问一句，免得对着没注册的号发消息。
  # 返回的 jid 才是发送用的地址（个别号码回来的 JID 与输入号码不同）。
  def check_number(inbox_id, phone)
    post("/sessions/#{inbox_id}/check-number", { phone: phone })
  end

  private

  def base_url
    ENV.fetch('WHATSAPP_BRIDGE_URL')
  end

  def headers
    { 'Content-Type' => 'application/json', 'X-Bridge-Token' => ENV.fetch('WHATSAPP_BRIDGE_TOKEN', '') }
  end

  def get(path)
    handle HTTParty.get("#{base_url}#{path}", headers: headers)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise BridgeError, "连不上 WhatsApp 桥接：#{e.message}"
  end

  def post(path, body = {})
    handle HTTParty.post("#{base_url}#{path}", headers: headers, body: body.to_json)
  rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise BridgeError, "连不上 WhatsApp 桥接：#{e.message}"
  end

  def handle(response)
    raise BridgeError, "bridge error #{response.code}: #{response.body}" unless response.success?

    response.parsed_response
  end
end
