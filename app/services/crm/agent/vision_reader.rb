# 读图片附件：把客户拍来的规格表、手写询价、实物照看成文字。
#
# 为什么值得做：近 180 天 3607 封客户来信里，448 封带内容图（约 1/8），
# 而这些图恰恰信息密度最高——手机拍的规格表、手写的数量单价。
# 以前业务员得自己点开看、自己敲进系统。
#
# 用的就是主模型那把 key：2026-10-27 实测 deepseek-chat 本身能读图
# （deepseek-flash 也能但是推理模型、token 吃得凶；deepseek-v4-pro 明确答「无法查看」）。
# 所以不另开一套 vision 配置——没有第二个需求之前，多一套 key/base/model
# 只是多一处会配错、会过期的地方。要换读图模型时再加不迟。
#
# ⚠️ 真正要紧的是下面那层过滤，不是调用本身：
# 同期 5067 张图里 3733 张是 Outlook 签名的 image001.png 这类，3297 张小于 20KB。
# 不挡掉的话，十次视觉调用有七次花在读别人的签名 logo 上。
class Crm::Agent::VisionReader
  # 小于这个尺寸的图基本不可能是内容：签名档 logo、社交图标、分隔线。
  MIN_CONTENT_BYTES = 200_000
  # 邮件客户端给内嵌图起的名字（Outlook 的 image001.png、WPS 的 ~wrd1.jpg…）。
  # 够大的即使叫这个名也读——有人确实把规格图直接贴进正文。
  SIGNATURE_NAME = /\A(image\d*|inline-image|~wrd\d*)\.(png|jpe?g|gif)\z/i

  # 单张图上限。生产里见过 11MB 的手机原图，整张塞进请求又慢又贵。
  # 超了就让用户自己看——比悄悄截断、读出半张图上的数字强。
  MAX_BYTES = 8.megabytes

  # 问法要具体：只说「描述这张图」，模型会写一段散文；
  # 这里要的是能直接拿去建报价单/PI 的明细，格式和 read_attachment 其它分支对齐。
  PROMPT = '这是外贸客户发来的图片。把图里**所有文字**原样读出来；' \
           '如果是报价表、规格表或订单，按「型号 | 描述 | 数量 | 单价」一行一项排好；' \
           '如果是实物照片，描述看得见的产品特征（型号标签、尺寸、接口、铭牌上的字）。' \
           '看不清的地方直说看不清，不要猜——读错一个数字比读不出更糟。'

  def initialize(account)
    @account = account
    @settings = Crm::AiSetting.for_account(account)
  end

  def enabled? = api_key.present?

  # 这张图值不值得花一次调用。
  def self.worth_reading?(blob)
    return false unless blob.content_type.to_s.start_with?('image/')
    return true if blob.byte_size.to_i > MIN_CONTENT_BYTES

    !blob.filename.to_s.match?(SIGNATURE_NAME)
  end

  def read(blob)
    return '系统还没配 AI Key，读不了图。' if api_key.blank?

    if blob.byte_size.to_i > MAX_BYTES
      return "这张图 #{(blob.byte_size / 1.megabyte.to_f).round(1)}MB，超过 #{MAX_BYTES / 1.megabyte}MB 的上限，没读，请自己打开看。"
    end

    with_tempfile(blob) { |path| chat.ask(PROMPT, with: { image: path }).content.to_s }
  rescue RubyLLM::Error, Faraday::Error => e
    "读图失败：#{e.message.to_s.truncate(120)}"
  end

  private

  def api_key = @settings.api_key.presence || ENV.fetch('DEEPSEEK_API_KEY', nil).presence

  def chat
    RubyLLM.context do |config|
      config.openai_api_key = api_key
      config.openai_api_base = @settings.api_base.presence || Crm::EmailAiService::DEFAULT_API_BASE
      config.openai_use_system_role = true
      config.request_timeout = Crm::EmailAiService::REQUEST_TIMEOUT
    end.chat(model: @settings.model.presence || Crm::EmailAiService::DEFAULT_MODEL,
             provider: :openai, assume_model_exists: true)
  end

  # 落成本机临时文件再喂给模型。
  #
  # 不生成公开链接：附件是客户的私有资料，不该为了让模型读就造一个谁拿到都能打开的外链。
  # 也不能直接塞 data URI——RubyLLM 的 with: 收的是**路径**，塞 data URI 它会当成文件名
  # 去 open，报「文件名超长」（2026-10-27 实测，错误信息还被模型转述成「图片打不开」，
  # 更难查）。扩展名要给对：有些实现按后缀判 MIME。
  def with_tempfile(blob)
    ext = File.extname(blob.filename.to_s).presence || ".#{blob.content_type.to_s.split('/').last}"
    file = Tempfile.new(['crm-vision', ext])
    file.binmode
    file.write(blob.download)
    file.flush
    yield file.path
  ensure
    file&.close
    file&.unlink
  end
end
