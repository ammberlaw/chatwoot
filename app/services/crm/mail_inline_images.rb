# 邮件正文里的内联 base64 图（data:image/...;base64,...）落成附件，正文只留访问链接。
#
# 为什么要做：有些客户/货代的签名把 logo 直接嵌进 HTML，一张图就十几万字符。
# 正文因此被顶到 Crm::Email::BODY_MAX_LENGTH 截断；回复时整段原样引用，
# 两三轮下来就发不出去（Body html is too long）。落成附件后正文能小一个数量级
# ——实测某条货代往来 199992 → 28305 字符。
module Crm::MailInlineImages
  # 只处理有分量的图（base64 ≥ 1000 字符 ≈ 750 字节）：1x1 占位图/小图标转成附件
  # 反而多出一堆没用的 blob。
  DATA_URI_RE = %r{data:(image/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]{1000,})}i

  module_function

  # 返回 [改写后的 html, 新建的 blob 数组]。blob 交给调用方 attach 到邮件上
  # （收信时邮件记录还没建出来，所以这里只建 blob 不挂载）。
  def extract(html)
    blobs = []
    rewritten = html.to_s.gsub(DATA_URI_RE) do |match|
      # 先取完捕获组再调用别的方法：build_blob 内部的正则会覆盖 last_match。
      content_type = Regexp.last_match(1)
      payload = Regexp.last_match(2)
      blob = build_blob(content_type, payload)
      next match unless blob

      blobs << blob
      Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    end
    [rewritten, blobs]
  end

  def build_blob(content_type, payload)
    data = Base64.decode64(payload.gsub(/\s/, ''))
    return nil if data.blank?

    ext = content_type.split('/').last.downcase.sub('jpeg', 'jpg')
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data),
      filename: "inline_#{SecureRandom.hex(6)}.#{ext}",
      content_type: content_type,
      metadata: { 'inline' => true }
    )
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailInlineImages] blob failed: #{e.message}")
    nil
  end
end
