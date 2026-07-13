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

  private

  def register_open(email)
    return if email.opens.where(ip_address: request.remote_ip).exists?(created_at: 10.seconds.ago..)

    email.register_open!(ip: request.remote_ip, user_agent: request.user_agent)
  end
end
