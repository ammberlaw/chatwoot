# 欧盟官方增值税号验证（VIES）。免费、不需要注册、不需要 key。
#
# 它回答的是一件别处问不到的事：**这个号是不是真的、现在还活着**。
# 空壳公司、注销掉的公司、官网上印着个假号的，这一道就挡掉了。
#
# ⚠️ 返回什么**按成员国不同**（2026-11-07 实测）：
#   意大利 → valid + 公司全名 + 注册地址
#   德国   → 只有 valid，name/address 一律是 "---"，连「名字对不对」都不给判
# 所以别指望它给公司名；拿得到是赚的，拿不到也有 valid 这一个比特。
#
# ⚠️ 有并发限流，撞上了返回 MS_MAX_CONCURRENT_REQ。这不是错误、更不是「号是假的」，
# 是「这会儿别问」——所以限流和验不过必须分开表示，否则会把正经公司标成可疑。
class Crm::ViesClient
  ENDPOINT = 'https://ec.europa.eu/taxation_customs/vies/rest-api/check-vat-number'.freeze
  TIMEOUT = 12
  BUSY = 'MS_MAX_CONCURRENT_REQ'.freeze

  # 🔴 Accept-Encoding 必须显式写 identity，**别删**。
  # Ruby 的 Net::HTTP 默认发 `gzip;q=1.0,deflate;q=0.6,identity;q=0.3`，
  # 欧盟这个站点收到之后 TLS 连接直接崩，报 `SSL_read: record layer failure`——
  # 错在 TLS 层，看着像证书或网络问题，其实是个请求头。
  # 2026-11-07 排查：同一台机器 curl 全通、Ruby 全挂，四种请求头组合里只有带
  # identity 的两种能拿到 200。
  HEADERS = { 'Content-Type' => 'application/json', 'Accept' => 'application/json',
              'Accept-Encoding' => 'identity' }.freeze

  # 返回 { status: 'valid' | 'invalid' | 'busy' | 'error', name:, address: }。
  def self.check(country_code, number)
    resp = HTTParty.post(ENDPOINT, body: { countryCode: country_code, vatNumber: number }.to_json,
                                   headers: HEADERS, timeout: TIMEOUT)
    parse(resp.parsed_response)
  rescue StandardError => e
    Rails.logger.info("[Crm::Vies] #{country_code}#{number}: #{e.class} #{e.message}")
    { status: 'error' }
  end

  def self.parse(body)
    return { status: 'error' } unless body.is_a?(Hash)

    errors = Array(body['errorWrappers']).pluck('error')
    return { status: 'busy' } if errors.include?(BUSY)
    return { status: 'error' } if errors.any?

    { status: body['valid'] ? 'valid' : 'invalid',
      name: present_or_nil(body['name']), address: present_or_nil(body['address']) }.compact
  end
  private_class_method :parse

  # 不披露的成员国返回的是 "---"，当成空。
  def self.present_or_nil(value)
    value.to_s.strip.delete('-').presence && value.to_s.strip
  end
  private_class_method :present_or_nil
end
