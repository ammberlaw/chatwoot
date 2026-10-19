# 名片识别：把照片直接交给带视觉的模型读成结构化字段，一步到位。
#
# 为什么不走「OCR 认字 + 模型分字段」两步：名片版式乱、中英外文混排，
# OCR 把字认出来之后行与行的归属还得猜；视觉模型看得到版面（谁字大、谁在谁下面），
# 分字段反而更准，还少一次网络往返，也省掉一个 OCR 服务商的账和钱。
#
# key 和端点直接复用「AI 设置」里那套（Crm::AiSetting），不另配——
# 只有模型名要单独写死：设置页配的 deepseek-chat 不认图片，认图片的是 deepseek-flash
# （2026-10-19 实测：flash 看图正常，v4-pro 回「无法识别图片内容」）。
# 换模型或换家时改 MODEL 一个常量即可，上层都不用动。
class Crm::VisionCardReader
  class Error < StandardError; end
  class NotConfigured < Error; end

  MODEL = 'deepseek-flash'.freeze
  TIMEOUT = 40

  # 名片图片别传原图：手机随手一拍就是三四兆，base64 之后更大，
  # 既慢又容易把模型的图片尺寸上限顶穿。
  MAX_BYTES = 4 * 1024 * 1024

  PROMPT = <<~TEXT.freeze
    这是一张名片的照片。读出上面的信息，填成 JSON。
    名片多为外贸展会所得，常见中英混排，也可能是德语、西班牙语、阿拉伯语等。
    规则：
    - 公司名取抬头那家公司，不要把网址、口号、经营范围当公司名；带 Co., Ltd./GmbH/S.A. 等后缀的那一行优先。
    - 人名和职位分开：Manager / Director / CEO / 经理 / 总监 这类是职位，不是名字。
    - 一张名片常有多个号码：手机和座机都填 contact_phone（只填一个，优先手机）；
      明确标着 WhatsApp / WeChat 的号码填 whats_app。号码保留国际区号的 + 号和数字，去掉空格和括号。
    - 邮箱全部转小写。网址去掉 http:// 和 https:// 前缀。
    - country 只能从下面这份列表里原样挑一个，不在列表里的一律给 null：
      %<countries>s
      只有从地址、电话区号、域名后缀能明确推断时才填，拿不准就给 null，绝不猜。
    - raw_text 放你在名片上读到的**全部文字**，按原来的行序，一行一行换行隔开。
      校对的人要拿它跟照片核对，所以照抄，不要整理、不要翻译。
    - 看不清或没有的字段给 null，绝不编造。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。字段：
    {"company_name":…,"contact_name":…,"job_title":…,"contact_phone":…,"whats_app":…,
     "contact_email":…,"website":…,"country":…,"address":…,"raw_text":…}
  TEXT

  def initialize(account:)
    @account = account
    @setting = Crm::AiSetting.for_account(account)
  end

  def api_key
    @api_key ||= @setting.api_key.presence || ENV.fetch('DEEPSEEK_API_KEY', nil)
  end

  # 设置页存的 api_base 已经带 /v1 了（生产上是 https://api.deepseek.com/v1）。
  def api_base
    @api_base ||= (@setting.api_base.presence || 'https://api.deepseek.com/v1').sub(%r{/+$}, '')
  end

  def configured? = api_key.present?

  # 返回 Hash（字段见 PROMPT）。调不通/读不出都抛，由 Parser 落成 parse_error。
  def read(image_bytes, content_type)
    raise NotConfigured, '还没配 AI 的 key（在「AI 设置」页里填）' unless configured?
    raise Error, "照片太大了（#{(image_bytes.bytesize / 1024.0 / 1024).round(1)}MB），重拍一张" if image_bytes.bytesize > MAX_BYTES

    parse(post(image_bytes, content_type))
  end

  private

  def post(image_bytes, content_type)
    data_uri = "data:#{content_type.presence || 'image/jpeg'};base64,#{Base64.strict_encode64(image_bytes)}"
    body = {
      model: MODEL,
      messages: [{ role: 'user', content: [
        { type: 'image_url', image_url: { url: data_uri } },
        { type: 'text', text: format(PROMPT, countries: Crm::Customer::COUNTRIES.join(' ')) }
      ] }]
    }
    resp = Faraday.post("#{api_base}/chat/completions") do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.body = body.to_json
      req.options.timeout = TIMEOUT
      req.options.open_timeout = 10
    end
    resp
  rescue Faraday::Error => e
    raise Error, "识别服务连不上：#{e.message}"
  end

  def parse(resp)
    json = JSON.parse(resp.body.to_s)
    # 鉴权失败、余额不足、模型名写错都走这里，原样把话带给用户——
    # 这类问题一看提示就知道该去哪改，翻译成「识别失败」反而耽误事。
    raise Error, "识别服务报错：#{json.dig('error', 'message') || resp.status}" if json['error'] || resp.status >= 400

    content = json.dig('choices', 0, 'message', 'content').to_s
    raise Error, '识别服务没有返回内容' if content.blank?

    extract_json(content)
  rescue JSON::ParserError
    raise Error, "识别服务返回了看不懂的内容（HTTP #{resp.status}）"
  end

  # 模型偶尔会在 JSON 外面裹一层说明或 ```json 代码块，取最外层那对花括号。
  def extract_json(content)
    raw = content[/\{.*\}/m]
    raise Error, '没从识别结果里读出字段' if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    raise Error, '识别结果不是合法 JSON'
  end
end
