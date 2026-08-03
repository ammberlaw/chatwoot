# 邮件 AI 助手（DeepSeek，OpenAI 兼容接口）：写信/翻译/往来摘要。
# 密钥优先读账户的 Crm::AiSetting（管理员在 CRM 后台「AI 设置」页配置，全公司共用一把）；
# 未配置时降级读环境变量 DEEPSEEK_API_KEY/_MODEL/_API_BASE，默认 deepseek-chat 官方端点。
# test/测试连接场景可传 api_key/api_base/model 覆盖，用后台表单里未保存的值先验一把。
class Crm::EmailAiService
  class NotConfigured < StandardError; end

  DEFAULT_API_BASE = 'https://api.deepseek.com/v1'.freeze
  DEFAULT_MODEL = 'deepseek-chat'.freeze

  def initialize(account:, api_key: nil, api_base: nil, model: nil)
    @account = account
    @override_key = api_key
    @override_base = api_base
    @override_model = model
  end

  COMPOSE_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的资深外贸业务员邮件助手，根据用户的中文意图代写发给客户的商务邮件。
    要求：
    - 默认用英文写；若意图里明确指定了其他语言，用指定语言。
    - 语气专业、简洁、友好，符合外贸函电习惯，不堆砌客套话。
    - 若提供了原邮件/已有内容，写成针对它的回复，回应其中的问题和要点。
    - 正文用纯文本分段，不要 Markdown 标记，不要写署名落款（系统会自动附加签名）。
    - 只输出邮件本身：第一行以「SUBJECT: 」开头给出主题，空一行后输出正文，不要任何解释。
  PROMPT

  TRANSLATE_SYSTEM = <<~PROMPT.freeze
    你是专业的外贸邮件翻译，把邮件忠实翻译成简体中文。
    要求：术语准确、保留段落结构；人名、公司名、产品型号、单证缩写（PI/CI/BL 等）保留原文。
    只输出翻译结果：第一行以「SUBJECT: 」开头给出主题译文，空一行后输出正文译文，不要任何解释。
  PROMPT

  SUMMARIZE_SYSTEM = <<~PROMPT.freeze
    你是外贸 CRM 的邮件助理。根据我方与对方的邮件往来记录（按时间先后排列），用简体中文输出简明摘要，分四部分列点：
    ① 谈到哪一步；② 对方的关注点或异议；③ 我方承诺的待办；④ 建议的下一步动作。
    用短句，总共不超过 250 字；记录太少不足以判断时如实说明，不要编造。
  PROMPT

  # 写信/回信：返回 [主题, 正文]。original 为回复场景带入的原文引用（可含用户已写内容）。
  def compose(intent:, original: nil)
    prompt = "写信意图：#{intent}"
    prompt += "\n\n原邮件/已有内容：\n#{truncate(original)}" if original.present?
    split_subject(ask(COMPOSE_SYSTEM, prompt))
  end

  # 来信翻译成中文：返回 [主题译文, 正文译文]。
  def translate(subject:, body:)
    split_subject(ask(TRANSLATE_SYSTEM, "SUBJECT: #{subject}\n\n#{truncate(body)}"))
  end

  # 往来摘要：transcript 由控制器拼好（时间/方向/主题/正文节选）。
  def summarize(transcript:)
    ask(SUMMARIZE_SYSTEM, transcript)
  end

  # 连接测试：用当前（含覆盖）配置发一个极短请求，能拿到任何回复即视为连通。
  def test!
    ask('你是连接测试助手。', '请只回复两个字：正常')
    true
  end

  private

  def ask(system_prompt, user_prompt)
    context = RubyLLM.context do |config|
      config.openai_api_key = api_key
      config.openai_api_base = api_base
      # DeepSeek 只认 system 角色，不认 OpenAI 新的 developer 角色
      config.openai_use_system_role = true
    end
    chat = context.chat(model: model, provider: :openai, assume_model_exists: true)
    chat.with_instructions(system_prompt)
    chat.ask(user_prompt).content.to_s.strip
  end

  def setting
    @setting ||= Crm::AiSetting.for_account(@account)
  end

  def api_key
    key = @override_key.presence || setting.api_key.presence || ENV['DEEPSEEK_API_KEY'].presence
    key || raise(NotConfigured, '还没配置 AI：请到「邮件中心 → AI 设置」填入 API Key')
  end

  def api_base
    @override_base.presence || setting.api_base.presence || ENV['DEEPSEEK_API_BASE'].presence || DEFAULT_API_BASE
  end

  def model
    @override_model.presence || setting.model.presence || ENV['DEEPSEEK_MODEL'].presence || DEFAULT_MODEL
  end

  # 「SUBJECT: xxx\n\n正文」拆成 [主题, 正文]；模型没按格式给主题时主题为 nil。
  def split_subject(text)
    return [Regexp.last_match(1).strip, Regexp.last_match(2).strip] if text =~ /\A\s*SUBJECT[:：]\s*(.+?)\n+(.*)\z/m

    [nil, text]
  end

  # 控制送入模型的文本长度，防超长邮件撑爆上下文。
  def truncate(text, max = 6000)
    text.to_s.length > max ? "#{text.to_s[0, max]}\n…（内容过长已截断）" : text.to_s
  end
end
