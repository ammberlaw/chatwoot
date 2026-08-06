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

  COMPANY_SYSTEM = <<~PROMPT.freeze
    你是资深外贸商务分析助手，负责给一家海外客户公司做背景初判（背调）。
    下面给你的是这家公司官网抓取到的文本，请严格只依据这些内容判断，不要凭空编造；
    官网没提到的字段填 "未提及"。用简体中文。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。字段：
    {
      "company_name": "公司正式名称",
      "business": "主营业务/主要产品，一到两句话说清楚它是做什么的",
      "industry": "所属行业",
      "size_hint": "规模线索：员工数、成立年份、工厂/门店、覆盖市场等，官网提到才写",
      "country": "国家或地区",
      "legit": "看起来是否为正常运营的真实公司，只填三选一：real / suspicious / unknown",
      "note": "给业务员的一句话判断或提醒（例如是否值得重点跟进、是同行还是终端客户等）"
    }
  PROMPT

  KPI_SCORING_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的绩效考核助手，帮主管给下属月度考核的每条指标打「建议分」。这只是给主管参考，最终分由主管决定。
    评分规则：
    - 每条指标的满分等于它的「权重」分值。根据员工完成值相对考核标准/目标值的达成情况给分：达标给满分附近；超额可上浮，但整体不超过「单项计分上限」百分比（如上限 120% 即最多为权重×1.2）；未达标按差距扣分；完全没做给 0 或接近 0。
    - 完成值为空、或据现有信息无法判断达成情况时，给一个保守的中间偏低分，并在理由里注明「完成值缺失，需主管核实」，不要编造完成情况。
    - 每条理由用简体中文一句话（不超过 40 字），说清给这个分的依据，只依据我提供的标准和完成值，不要臆测。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。格式：
    {
      "suggestions": [
        { "i": 0, "score": 7.5, "reason": "回款率 6.2% 达标，接近目标给近满分" }
      ]
    }
    其中 i 是指标序号（从 0 开始，对应我给你的「指标N」），score 是建议分（数字，可含一位小数），每条指标都要给出一项。
  PROMPT

  PI_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的单证助手，从形式发票（Proforma Invoice, PI）的文本里抽取建订单所需字段。
    文本可能来自 PDF 或 Excel（表格已按行拼成文本），排版可能凌乱，请尽力理解。
    规则：
    - 「客户」取买方（Buyer / Messrs / To / Consignee / Sold to），不要取卖方（我方/Seller/Beneficiary/Shipper）。
    - 金额只保留数字，去掉货币符号和千分位逗号；币种用三位字母代码（USD/CNY/EUR…），见 $ 默认 USD、￥/RMB 默认 CNY。
    - 日期统一成 YYYY-MM-DD；拿不准或没有就给 null。
    - 明细逐行抽取；单价/金额是对客户的售价（不是成本）。数量、单价、金额都只保留数字。
    - 没有的字段给 null，明细没有就给空数组，绝不编造。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。字段：
    {
      "pi_no": "PI 号",
      "order_date": "YYYY-MM-DD 或 null",
      "delivery_date": "YYYY-MM-DD 或 null",
      "customer_name": "买方公司名",
      "currency": "三位币种代码",
      "total_amount": 数字或 null,
      "line_items": [
        { "name": "品名", "spec": "规格/型号", "quantity": 数字, "unit_price": 数字, "amount": 数字 }
      ]
    }
  PROMPT

  # PI 识别：把 PI 文本（PDF/Excel 抽出的纯文本）抽成字段化 Hash，供销售订单自动填单。
  def pi_extract(text:)
    parse_json(ask(PI_SYSTEM, truncate(text, 12_000)))
  end

  # 绩效打分建议：为一张考核表的各指标算「建议分」。items 由控制器拼好，
  # 每项含 name/dimension/weight/standard/target/baseline/actual。返回 [{ 'i', 'score', 'reason' }, ...]。
  def score_suggestions(pass_score:, cap_pct:, items:)
    lines = items.each_with_index.map do |it, i|
      <<~ITEM.strip
        指标#{i}｜#{it[:name]}（维度：#{it[:dimension].presence || '—'}，满分权重：#{it[:weight]}）
          考核标准：#{it[:standard].presence || '—'}
          目标值：#{it[:target].presence || '—'}；基准值：#{it[:baseline].presence || '—'}
          员工完成值：#{it[:actual].presence || '（未填）'}
      ITEM
    end.join("\n\n")
    raw = ask(KPI_SCORING_SYSTEM, "及格线：#{pass_score}；单项计分上限：#{cap_pct}%\n\n#{lines}")
    Array(parse_json(raw)['suggestions'])
  end

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

  # 公司背调：site_text 为官网抓取的文本（由 Crm::CompanyLookupService 提供），返回字段化 Hash。
  def company_profile(domain:, site_text:)
    raw = ask(COMPANY_SYSTEM, "公司域名：#{domain}\n\n官网内容：\n#{truncate(site_text)}")
    parse_json(raw)
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

  # 从模型回复里抽出 JSON 对象；模型偶尔会加解释或代码块，取第一个 {...} 块解析。
  def parse_json(raw)
    json = raw.to_s[/\{.*\}/m]
    json ? JSON.parse(json) : { 'note' => raw.to_s }
  rescue JSON::ParserError
    { 'note' => raw.to_s }
  end
end
