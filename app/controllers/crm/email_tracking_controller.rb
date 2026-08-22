# 邮件追踪像素回调（公开、免登录）：收件人邮件客户端加载像素即命中此处，
# 记录一次打开（时间 + IP + UA），然后返回 1×1 透明图。
# 短窗口去重，避免同一次渲染重复计数。
class Crm::EmailTrackingController < PublicController
  def show
    email = Crm::Email.find_by(tracking_token: params[:token])
    register_open(email) if email

    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    send_file Rails.public_path.join('assets/images/tracking-pixel.png'), type: 'image/png', disposition: 'inline'
  end

  # 链接点击回调（公开、免登录）：记录一次点击（含目标 URL），然后 302 跳转到原地址。
  def click
    email = Crm::Email.find_by(tracking_token: params[:token])
    target = params[:u].to_s
    ok = valid_http_url?(target)
    register_click(email, target) if email && ok
    redirect_to(ok ? target : root_url, allow_other_host: true)
  end

  private

  def register_open(email)
    return if email.opens.where(ip_address: request.remote_ip).exists?(created_at: 10.seconds.ago..)

    email.register_open!(ip: request.remote_ip, user_agent: request.user_agent)
  end

  # 短窗口去重（同 IP + 同链接 10 秒内不重复计数），避免预取/重复渲染虚增。
  def register_click(email, url)
    return if email.clicks.where(ip_address: request.remote_ip, url: url).exists?(created_at: 10.seconds.ago..)

    email.register_click!(url: url, ip: request.remote_ip, user_agent: request.user_agent)
  end

  # 只跳转 http/https，挡掉 javascript:/data: 等，避免被当跳板。
  def valid_http_url?(url)
    return false if url.blank?

    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end
end
