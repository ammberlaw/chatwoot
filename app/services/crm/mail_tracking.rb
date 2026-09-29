# 我们埋在发出邮件里的追踪件（1×1 打开像素 + 带 token 的点击跳转链接），会被客户的回信
# 原样引用回来。这份副本一旦在 CRM 里被自己人读到，浏览器就会去加载那个像素，于是记成
# 「客户又打开了一次」——已读/点击数被自己人顶高，深圳、东莞的 IP 混进客户的阅读记录里。
# 所以收到的邮件入库前先把我们自己的追踪件剥掉（只认我们自己生成的那两条路径，不碰客户内容）。
module Crm::MailTracking
  TOKEN = /[0-9a-f]{40}/
  OPEN_PATH = %r{/crm_email_open/#{TOKEN}\.png}
  CLICK_PATH = %r{/crm_email_click/#{TOKEN}}

  # ① 打开像素本体：<img … src="…/crm_email_open/<token>.png" …>
  OPEN_PIXEL = /<img\b[^>]*\bsrc=["'][^"']*#{OPEN_PATH}[^"']*["'][^>]*>/i
  # ② 正文被截断过的老邮件里，像素被降级成了一条链接，整个 <a> 一起去掉
  OPEN_ANCHOR = %r{<a\b[^>]*\bhref=["'][^"']*#{OPEN_PATH}[^"']*["'][^>]*>.*?</a>}im
  # ③ 点击跳转：还原成原地址——引用里的链接照样点得开，只是不再算进我们的点击数。
  #    href 属性里的和被当成可见文字写出来的，一并处理。
  #    有的客户端会把 ?u= 的等号写成实体 &#61;，两种都要认。
  CLICK_URL = %r{https?://[^\s"'<>]*#{CLICK_PATH}\?u(?:=|&\#61;)(?<url>[^\s"'<>]+)}i
  # ④ 漏网的像素地址（写进 alt、或当纯文字留着的），只是噪音，清掉
  OPEN_URL = %r{https?://[^\s"'<>]*#{OPEN_PATH}}i

  def self.strip_own(html)
    return html if html.blank?

    html.gsub(OPEN_PIXEL, '')
        .gsub(OPEN_ANCHOR, '')
        .gsub(CLICK_URL) { decode(Regexp.last_match[:url]) }
        .gsub(OPEN_URL, '')
  end

  # 剥不干净也不能把正文弄坏：还原失败就原样留着跳转链接（最多多记一次点击）。
  def self.decode(escaped)
    CGI.unescape(escaped)
  rescue StandardError
    escaped
  end
end
