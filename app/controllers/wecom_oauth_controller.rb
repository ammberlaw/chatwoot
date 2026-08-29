# 企业微信工作台「免密登录」入口（无需登录态）。
#   /wecom/enter    工作台应用主页指向这里 → 跳企业微信静默授权
#   /wecom/callback 企业微信带 code 回跳 → 拿成员邮箱 → 匹配 CRM 账号 → 签发 SSO 令牌跳登录页自动进
# 复用 Chatwoot 既有 SSO 令牌机制（与 Google OAuth 同款），只做“企业微信身份 → 邮箱”这一段。
class WecomOauthController < ActionController::Base
  def enter
    unless Crm::WecomOauthService.configured?
      return render plain: '企业微信登录尚未配置，请联系管理员。', status: :ok
    end

    redirect_to Crm::WecomOauthService.authorize_url(callback_url), allow_other_host: true
  end

  def callback
    email = Crm::WecomOauthService.new.email_from_code(params[:code])
    user = email.present? ? User.from_email(email) : nil

    if user.nil?
      return render plain: not_matched_message(email), status: :ok
    end

    redirect_to sso_login_url(user), allow_other_host: true
  end

  private

  def callback_url
    "#{site_origin}/wecom/callback"
  end

  def sso_login_url(user)
    "#{site_origin}/app/login?email=#{ERB::Util.url_encode(user.email)}" \
      "&sso_auth_token=#{user.generate_sso_auth_token}"
  end

  # 优先用配置的 FRONTEND_URL（生产为 https://wintouchspace.com），兜底用当前请求域名。
  def site_origin
    ENV.fetch('FRONTEND_URL', "#{request.protocol}#{request.host_with_port}").chomp('/')
  end

  def not_matched_message(email)
    if email.present?
      "未找到与企业微信邮箱（#{email}）匹配的系统账号。请管理员在企业微信通讯录里，把该成员的邮箱设为其 CRM 登录邮箱。"
    else
      '未能从企业微信获取到邮箱。请管理员在通讯录里为该成员填写邮箱（设为其 CRM 登录邮箱）。'
    end
  end
end
