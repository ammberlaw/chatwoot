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

  def logout(inbox_id)
    post("/sessions/#{inbox_id}/logout")
  end

  def send_text(inbox_id, phone, text)
    body = post("/sessions/#{inbox_id}/send", { phone: phone, text: text })
    body['message_id']
  end

  # 发附件：把附件的公开链接交给桥接，由它取回字节再经 Baileys 发出去
  # （几 MB 的 PI/图纸走 base64 会把请求体撑得很难看）。
  def send_media(inbox_id, phone, media)
    body = post("/sessions/#{inbox_id}/send-media", media.slice(:url, :filename, :mimetype, :caption).merge(phone: phone))
    body['message_id']
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
  end

  def post(path, body = {})
    handle HTTParty.post("#{base_url}#{path}", headers: headers, body: body.to_json)
  end

  def handle(response)
    raise BridgeError, "bridge error #{response.code}: #{response.body}" unless response.success?

    response.parsed_response
  end
end
