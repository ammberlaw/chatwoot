# 企业微信（WeCom）网页 OAuth：把工作台点进来的成员换成企业成员邮箱，用于免密登录匹配 CRM 账号。
# 凭证走生产环境变量（一次性基础设施配置）：WECOM_CORP_ID / WECOM_AGENT_ID / WECOM_SECRET。
# 企业成员点应用 → snsapi_base 静默授权拿 code → 换 userid → 查通讯录拿 email。
# qyapi.weixin.qq.com 为腾讯国内服务器，生产机可直连。
class Crm::WecomOauthService
  QYAPI = 'https://qyapi.weixin.qq.com'.freeze
  AUTHORIZE = 'https://open.weixin.qq.com/connect/oauth2/authorize'.freeze
  TOKEN_CACHE_KEY = 'wecom:access_token'.freeze

  class << self
    def corp_id = ENV['WECOM_CORP_ID'].presence
    def agent_id = ENV['WECOM_AGENT_ID'].presence
    def secret = ENV['WECOM_SECRET'].presence
    def configured? = corp_id.present? && agent_id.present? && secret.present?

    # 工作台点击后先跳到这个授权地址，企业微信静默授权后带 code 回跳 redirect_uri。
    def authorize_url(redirect_uri)
      query = {
        appid: corp_id, redirect_uri: redirect_uri, response_type: 'code',
        scope: 'snsapi_base', agentid: agent_id, state: 'wintouch'
      }
      "#{AUTHORIZE}?#{query.to_query}#wechat_redirect"
    end
  end

  # code → 企业成员邮箱（优先通讯录邮箱，其次企业邮箱）。任一步失败返回 nil。
  def email_from_code(code)
    return if code.blank?

    userid = fetch_userid(code)
    return if userid.blank?

    detail = fetch_user_detail(userid)
    (detail['email'].presence || detail['biz_mail'].presence)&.downcase
  end

  private

  def access_token
    @access_token ||= (::Redis::Alfred.get(TOKEN_CACHE_KEY).presence || fetch_and_cache_token)
  end

  def fetch_and_cache_token
    res = get_json("#{QYAPI}/cgi-bin/gettoken",
                   corpid: self.class.corp_id, corpsecret: self.class.secret)
    token = res['access_token']
    ::Redis::Alfred.setex(TOKEN_CACHE_KEY, token, 6000) if token.present? # 官方有效期 7200s，留余量
    token
  end

  def fetch_userid(code)
    get_json("#{QYAPI}/cgi-bin/auth/getuserinfo", access_token: access_token, code: code)['userid']
  end

  def fetch_user_detail(userid)
    get_json("#{QYAPI}/cgi-bin/user/get", access_token: access_token, userid: userid)
  end

  def get_json(url, query)
    HTTParty.get(url, query: query, timeout: 8).parsed_response || {}
  rescue StandardError => e
    Rails.logger.error("[WeCom] #{url} 失败: #{e.message}")
    {}
  end
end
