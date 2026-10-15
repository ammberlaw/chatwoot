# 邮件 AI 助手（DeepSeek，OpenAI 兼容接口）：写信/翻译/往来摘要。
# 密钥优先读账户的 Crm::AiSetting（管理员在 CRM 后台「AI 设置」页配置，全公司共用一把）；
# 未配置时降级读环境变量 DEEPSEEK_API_KEY/_MODEL/_API_BASE，默认 deepseek-chat 官方端点。
# test/测试连接场景可传 api_key/api_base/model 覆盖，用后台表单里未保存的值先验一把。
class Crm::EmailAiService # rubocop:disable Metrics/ClassLength
  class NotConfigured < StandardError; end

  DEFAULT_API_BASE = 'https://api.deepseek.com/v1'.freeze
  DEFAULT_MODEL = 'deepseek-chat'.freeze
  # 调模型的超时：比 AI 接口 90 秒的请求时限早一点收手（见 config/initializers/rack_timeout.rb）。
  REQUEST_TIMEOUT = 85
  # 整封翻译的切段参数：一次 6000 字的上限对动辄几万字的往来邮件根本不够（正文会被
  # 「…（内容过长已截断）」切掉后半截）；直接把上限调大又会让单次请求拖过 Rack 的
  # 15 秒超时。所以切成小段并发跑，总耗时≈最慢那一段，而不是各段相加。
  TRANSLATE_CHUNK = 4000
  TRANSLATE_MAX_CHUNKS = 10

  # 附件单证类型（自动归档标签）：代码 => 中文标签。OTHER 兜底。前端按此显示徽标。
  DOC_TYPES = {
    'PI' => '形式发票', 'CONTRACT' => '合同/PO', 'QUOTE' => '报价单',
    'SPEC' => '规格书', 'PACKING' => '装箱单', 'BL' => '提单/物流',
    'INVOICE' => '商业发票', 'OTHER' => '其他'
  }.freeze

  # 文件名启发式（AI 未配置/失败时兜底）：按顺序匹配，先命中先返回。
  # PI 规则放在 INVOICE 之前，"proforma invoice" 才不会被当成商业发票。
  DOC_TYPE_HINTS = [
    ['PI', /\b(pi|proforma)\b|形式发票|pro[\s_-]?forma/i],
    ['PACKING', %r{packing|装箱|\bp[\s_/-]*l\b|pkl}i],
    ['BL', %r{bill of lading|提单|运单|waybill|\bawb\b|(?:^|[\s_/-])b[\s_/-]?l(?:$|[\s_/.-])}i],
    ['INVOICE', /commercial invoice|\bci\b|商业发票|invoice|发票/i],
    ['QUOTE', /quot|报价|offer sheet/i],
    ['CONTRACT', /contract|合同|\bpo\b|purchase order|订单/i],
    ['SPEC', /spec|规格|datasheet|drawing|图纸|技术|参数|manual/i]
  ].freeze

  def initialize(account:, api_key: nil, api_base: nil, model: nil)
    @account = account
    @override_key = api_key
    @override_base = api_base
    @override_model = model
  end

  COMPOSE_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的资深外贸业务员邮件助手，根据用户的中文意图代写发给客户的商务邮件。

    最重要的一条：【写信意图】是这封信唯一的内容来源。用户说几件事，你就写几件事——
    不要扩写成一封面面俱到的信，不要替用户表态。

    - 不得添加意图里没有的具体信息：价格、折扣、数量、交期、付款方式、保修、运费承担、
      任何承诺或条件，一律只能照搬意图里写明的。意图没说的就不写，缺信息也不要编一个填进去。
    - 【背景参考】只是让你了解上下文、把称呼和指代写对，**不是待办清单**。
      除非意图明确要求回应，否则不要逐条回答里面的问题——用户没打算在这封信里答的，就别替他答。
    - 默认用英文写；若意图里明确指定了其他语言，用指定语言。
    - 语气专业、简洁、友好，符合外贸函电习惯，不堆砌客套话；篇幅与意图的信息量相称。
    - 正文用纯文本分段，不要 Markdown 标记，不要写署名落款（系统会自动附加签名）。
    - 只输出邮件本身：第一行以「SUBJECT: 」开头给出主题，空一行后输出正文，不要任何解释。
  PROMPT

  TRANSLATE_SYSTEM = <<~PROMPT.freeze
    你是专业的外贸邮件翻译，把邮件忠实翻译成简体中文。
    要求：术语准确、保留段落结构；人名、公司名、产品型号、单证缩写（PI/CI/BL 等）保留原文。
    只输出翻译结果：第一行以「SUBJECT: 」开头给出主题译文，空一行后输出正文译文，不要任何解释。
  PROMPT

  # 长邮件要切成多段并行翻译。后续片段不能沿用上面那套提示词——那套要求「第一行给主题译文」，
  # 于是模型会给每一段都编一个主题出来，直接混进正文，读起来就前言不搭后语。
  TRANSLATE_PART_SYSTEM = <<~PROMPT.freeze
    你是专业的外贸邮件翻译。下面是同一封邮件的中间片段（不是完整邮件，开头结尾可能不成句）。
    把它忠实翻译成简体中文：术语准确、保留段落结构；人名、公司名、产品型号、单证缩写（PI/CI/BL 等）保留原文。
    只输出这一段的正文译文——不要主题行、不要「SUBJECT:」、不要补全缺失的句子、不要任何说明。
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
    - shipping_cost 取运费/freight/shipping cost 那一行的金额；PI 上没有单列运费就给 null，不要从总额里倒推。
    - 没有的字段给 null，明细没有就给空数组，绝不编造。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。字段：
    {
      "pi_no": "PI 号",
      "order_date": "YYYY-MM-DD 或 null",
      "delivery_date": "YYYY-MM-DD 或 null",
      "customer_name": "买方公司名",
      "currency": "三位币种代码",
      "total_amount": 数字或 null,
      "shipping_cost": 数字或 null,
      "line_items": [
        { "name": "品名", "spec": "规格/型号", "quantity": 数字, "unit_price": 数字, "amount": 数字 }
      ]
    }
  PROMPT

  DOC_CLASSIFY_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的单证归档助手。根据邮件主题和附件文件名，判断每个附件属于哪一类外贸单证。
    类别代码（只能从这些里选，别的一律 OTHER）：
    PI=形式发票(Proforma Invoice)；CONTRACT=合同/采购订单(Contract/PO)；QUOTE=报价单(Quotation)；
    SPEC=规格书/技术资料/图纸(Spec/Datasheet/Drawing)；PACKING=装箱单(Packing List)；
    BL=提单/物流单证(B/L/AWB/运单)；INVOICE=商业发票(Commercial Invoice)；OTHER=其他。
    只依据文件名和主题的字面线索判断，拿不准就给 OTHER，不要编造。
    只返回一个 JSON 对象，不要输出任何多余文字、不要用代码块包裹。格式：
    { "files": [ { "name": "原文件名", "type": "类别代码" } ] }
  PROMPT

  # PI 识别：把 PI 文本（PDF/Excel 抽出的纯文本）抽成字段化 Hash，供销售订单自动填单。
  def pi_extract(text:)
    parse_json(ask(PI_SYSTEM, truncate(text, 12_000)))
  end

  # 附件单证分类：传主题 + 文件名数组，返回 { 文件名 => 类型代码 }。
  # AI 优先；未配置/异常时逐个走文件名启发式兜底，保证一定有结果。
  def classify_attachments(subject:, filenames:)
    listing = filenames.each_with_index.map { |n, i| "#{i + 1}. #{n}" }.join("\n")
    raw = ask(DOC_CLASSIFY_SYSTEM, "邮件主题：#{subject}\n\n附件列表：\n#{listing}")
    ai = Array(parse_json(raw)['files']).to_h { |h| [h['name'].to_s, normalize_doc_type(h['type'])] }
    filenames.index_with { |n| ai[n].presence || heuristic_doc_type(n) }
  rescue StandardError => e
    Rails.logger.warn("[Crm::EmailAiService] classify_attachments fallback: #{e.message}")
    filenames.index_with { |n| heuristic_doc_type(n) }
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
    prompt = "【写信意图 · 这封信要写的就是这些】\n#{intent}"
    prompt += "\n\n【背景参考 · 仅供理解上下文，不是要回应的清单】\n#{truncate(original)}" if original.present?
    split_subject(ask(COMPOSE_SYSTEM, prompt))
  end

  # 来信翻译成中文：返回 [主题译文, 正文译文]。长邮件切段并发翻译，不再腰斩。
  def translate(subject:, body:)
    chunks, dropped = split_for_translation(body)
    warm_up_settings
    parts = in_parallel(chunks.each_with_index.to_a) do |chunk, idx|
      next ask(TRANSLATE_SYSTEM, "SUBJECT: #{subject}\n\n#{chunk}") if idx.zero?

      # 各段是并行翻的，互相看不到上下文；把主题捎上，术语才不会一段一个译法。
      ask(TRANSLATE_PART_SYSTEM, "（本邮件主题：#{subject}）\n\n#{chunk}")
    end
    head_subject, head_body = split_subject(parts.first.to_s)
    # 后续片段本不该有主题行，模型偶尔还是会带一行——兜底剥掉，别让它混进正文。
    rest = parts.drop(1).map { |part| split_subject(part.to_s).last }
    text = [head_body, *rest].compact_blank.join("\n\n")
    text += "\n\n…（原文过长，后面 #{dropped} 段未翻译）" if dropped.positive?
    [head_subject, text]
  end

  # 按行累积切段；单行本身超长（HTML 剥成纯文本后常整段挤成一行）就硬切。
  def split_for_translation(body)
    chunks = []
    buf = +''
    body.to_s.each_line do |line|
      slice_long_line(line).each do |piece|
        if !buf.empty? && buf.length + piece.length > TRANSLATE_CHUNK
          chunks << buf
          buf = +''
        end
        buf << piece
      end
    end
    chunks << buf unless buf.empty?
    chunks = [''] if chunks.empty?
    [chunks.first(TRANSLATE_MAX_CHUNKS), [chunks.size - TRANSLATE_MAX_CHUNKS, 0].max]
  end

  # 单行超长（HTML 剥成纯文本后常整段挤成一行）时，优先在句末、其次在空白处断开。
  # 从句子中间切开的话，切口两边的半句模型都译不对。
  def slice_long_line(line)
    pieces = []
    rest = line
    while rest.length > TRANSLATE_CHUNK
      window = rest[0, TRANSLATE_CHUNK]
      at = window.rindex(/[。！？；!?;]/) || window.rindex(/[.]\s/) || window.rindex(/\s/)
      cut = at ? at + 1 : TRANSLATE_CHUNK
      pieces << rest[0, cut]
      rest = rest[cut..]
    end
    pieces << rest unless rest.empty?
    pieces
  end

  # 通用翻译：把文本翻成指定语言（language 为语言名，如「简体中文」/「English」），
  # 只返回译文；保留原换行/HTML 结构。会话消息「翻译」用它替代 Google 翻译。
  def translate_text(text:, language:)
    system = <<~PROMPT
      你是专业翻译。把用户给的内容翻译成#{language}，只输出译文本身，不要加任何解释、前后缀或引号。
      保留原文的换行、段落与 HTML 标签结构；人名、公司名、产品型号、单证缩写（PI/CI/BL 等）可保留原文。
    PROMPT
    ask(system, truncate(text, 8000))
  end

  # 往来摘要：transcript 由控制器拼好（时间/方向/主题/正文节选）。
  def summarize(transcript:)
    ask(SUMMARIZE_SYSTEM, transcript)
  end

  PROGRESS_SYSTEM = <<~PROMPT.freeze
    你是外贸 CRM 的商机进度助手。下面是我方与某客户的邮件往来（按时间先后，最后一封是最新来信）。
    判断【最新这封来信】是否报告了一个"具体的业务进度事件"，例如：确认下单/签合同、付定金或尾款、
    确认样品、安排生产、通知发货、提供提单/物流单号、验收货物、提出重要投诉或索赔。
    只有出现这类可落地的进度才算；普通询价、寒暄、催促、报价往来不算。
    只返回一个 JSON 对象，不要多余文字、不要代码块。字段：
    {
      "update": true 或 false,
      "title": "不超过20字的进度短标题，如 客户已付30%定金",
      "body": "一句话补充关键信息（金额/单号/日期等），不超过60字",
      "stage_hint": "PENDING_PAYMENT/SAMPLING/WON/LOST 之一或 null（该进度暗示的商机阶段）",
      "next_step": "给业务员的下一步跟进建议，一句话、不超过30字、具体可执行（如 回复确认交期并催付定金）。无论 update 真假都要给出；信息太少就填 补充沟通了解需求"
    }
    title/body/stage_hint 在 update 为 false 时可留空，但 next_step 必须给。不要编造往来里没有的信息。
  PROMPT

  SUGGEST_SYSTEM = <<~PROMPT.freeze
    你是外贸 CRM 的销售助理。根据我方与客户的邮件往来和商机信息，给业务员一条"下一步该做什么"的具体建议。
    要求：简体中文，2~4 句，直接可执行（例如该回复什么、该催什么、该准备什么单证或样品）；
    只依据提供的信息，不编造；信息太少就说明还需要补充哪些沟通。不要寒暄、不要复述原文。
  PROMPT

  # 从往来里识别【最新来信】是否含具体业务进度事件，返回 { update, title, body, stage_hint }。
  def extract_progress(transcript:)
    parse_json(ask(PROGRESS_SYSTEM, truncate(transcript, 8000)))
  end

  # 下一步销售建议：返回一段可执行的中文建议文本。
  def suggest_next_step(transcript:)
    ask(SUGGEST_SYSTEM, truncate(transcript, 8000))
  end

  # 公司背调：site_text 为官网抓取的文本（由 Crm::CompanyLookupService 提供），返回字段化 Hash。
  def company_profile(domain:, site_text:)
    raw = ask(COMPANY_SYSTEM, "公司域名：#{domain}\n\n官网内容：\n#{truncate(site_text)}")
    parse_json(raw)
  end

  INVITE_SYSTEM = <<~PROMPT.freeze
    你是一家中国外贸公司的资深业务员，给海外客户写一封「展会邀约」邮件，邀请对方到我方展位参观洽谈。
    要求：
    - 默认用英文写；若客户所在国家主流商务语言另有其一（如西语国家可用英文即可），仍以英文为主，简洁得体。
    - 语气专业、热情但不啰嗦，突出「见面洽谈」的价值；结合展会名称、时间、地点、展位号、我方本次主打产品。
    - 若给了确认链接，请在正文自然位置放入该链接，并引导对方点击在线确认到访（One click to confirm your visit）。
    - 正文用纯文本分段，不要 Markdown 标记，不要写署名落款（系统会自动附加签名）。
    - 只输出邮件本身：第一行以「SUBJECT: 」开头给出主题，空一行后输出正文，不要任何解释。
  PROMPT

  # 展会邀约 4 步 SOP 各步的「模板」system 提示：只生成一份带占位符的模板（供邮件合并批量建草稿，
  # 一次 AI 调用即可，避免逐客户调用超时）。收件公司用 {{COMPANY}}、确认链接用 {{LINK}} 占位。
  STAGE_TEMPLATE_HINT = "\n收件人公司名请用占位符 {{COMPANY}} 表示；如需放确认到访链接，用占位符 {{LINK}} 表示。这两个标记原样保留、不要替换或翻译。".freeze
  STAGE_TEMPLATE_SYSTEMS = {
    'teaser' => (<<~PROMPT.freeze),
      你是一家中国外贸公司的资深业务员，写一封展会「预告」邮件模板（正式邀请函之前的预热）。
      要求：简短热情，告知我方将参加该展会、时间地点，请对方留意后续正式邀请；不要长篇。默认英文。
      正文纯文本分段、不要 Markdown、不写署名。只输出：第一行「SUBJECT: 」给主题，空一行后正文。#{STAGE_TEMPLATE_HINT}
    PROMPT
    'invite' => (<<~PROMPT.freeze),
      你是一家中国外贸公司的资深业务员，写一封展会「邀请函」邮件模板，邀请对方到我方展位参观洽谈。
      要求：专业热情不啰嗦，突出见面洽谈价值，结合展会名称/时间/地点/展位号/主打产品；自然位置放入确认链接引导在线确认。默认英文。
      正文纯文本分段、不要 Markdown、不写署名。只输出：第一行「SUBJECT: 」给主题，空一行后正文。#{STAGE_TEMPLATE_HINT}
    PROMPT
    'confirm' => (<<~PROMPT.freeze),
      你是一家中国外贸公司的资深业务员，写一封展会「确认到访」跟进邮件模板（已发过邀请函之后）。
      要求：礼貌跟进，请对方确认是否到访、引导点击确认链接，表达期待见面。默认英文。
      正文纯文本分段、不要 Markdown、不写署名。只输出：第一行「SUBJECT: 」给主题，空一行后正文。#{STAGE_TEMPLATE_HINT}
    PROMPT
    'reminder' => (<<~PROMPT.freeze)
      你是一家中国外贸公司的资深业务员，写一封展会「行前提醒」邮件模板（展会临近时发）。
      要求：提醒展会日期临近，重申展位号/地点、主打产品，欢迎莅临；简洁友好。默认英文。
      正文纯文本分段、不要 Markdown、不写署名。只输出：第一行「SUBJECT: 」给主题，空一行后正文。#{STAGE_TEMPLATE_HINT}
    PROMPT
  }.freeze

  # 4 步 SOP 某一步的邮件模板（带 {{COMPANY}}/{{LINK}} 占位，供批量合并建草稿）：返回 [主题模板, 正文模板]。
  def compose_stage_template(exhibition:, stage:)
    system = STAGE_TEMPLATE_SYSTEMS[stage.to_s] || STAGE_TEMPLATE_SYSTEMS['invite']
    ctx = [
      "展会名称：#{exhibition.name}",
      ("展会时间：#{exhibition.starts_on} ~ #{exhibition.ends_on}" if exhibition.starts_on),
      ("展会地点：#{[exhibition.city, exhibition.country, exhibition.venue].compact_blank.join('，')}" if exhibition.city || exhibition.venue),
      ("展位号：#{exhibition.booth_no}" if exhibition.booth_no.present?),
      ("我方本次主打产品：#{exhibition.featured_products}" if exhibition.featured_products.present?)
    ].compact_blank.join("\n")
    split_subject(ask(system, ctx))
  end

  # 展会邀约上下文（展会 + 客户 + 确认链接），供 4 步 SOP 各步复用。空字段自动略去。
  def invite_context(exhibition, customer, confirm_url)
    {
      '展会名称' => exhibition.name,
      '展会时间' => (exhibition.starts_on && "#{exhibition.starts_on} ~ #{exhibition.ends_on}"),
      '展会地点' => [exhibition.city, exhibition.country, exhibition.venue].compact_blank.join('，'),
      '展位号' => exhibition.booth_no,
      '我方本次主打产品' => exhibition.featured_products,
      '收件客户公司' => customer.name,
      '客户所在国家/地区' => [customer.trade_country, customer.trade_region].compact_blank.join('，'),
      '客户联系人' => customer.primary_contact_name,
      '在线确认到访链接' => confirm_url
    }.filter_map { |k, v| "#{k}：#{v}" if v.present? }.join("\n")
  end

  # 展会邀请函：按展会 + 客户信息生成邀约邮件，返回 [主题, 正文]。confirm_url 为客户在线确认到访的落地页链接。
  def compose_invite(exhibition:, customer:, confirm_url: nil)
    split_subject(ask(INVITE_SYSTEM, invite_context(exhibition, customer, confirm_url)))
  end

  # 连接测试：用当前（含覆盖）配置发一个极短请求，能拿到任何回复即视为连通。
  def test!
    ask('你是连接测试助手。', '请只回复两个字：正常')
    true
  end

  private

  # 并发前先把 AI 配置读出来：ask 里的 api_key/api_base/model 会查库，
  # 放到子线程里就是每个线程各借一条数据库连接，没必要也不安全。
  def warm_up_settings
    [api_key, api_base, model]
  end

  def in_parallel(items)
    return [yield(*items.first)] if items.size <= 1

    items.map { |args| Thread.new { yield(*args) } }.map(&:value)
  end

  def ask(system_prompt, user_prompt)
    with_deadline { chat_once(system_prompt, user_prompt) }
  end

  # Faraday 的 timeout 是**每次 read** 的超时，不是整轮的。模型侧挂住的时候这道闸刀
  # 根本不落：2026-10-15 DeepSeek 故障实测，首字节 0.07 秒就回了 200，之后只发
  # keep-alive 心跳、一个 token 都不吐——心跳把 read 超时一次次重置，请求就这么挂着，
  # 最后被 rack-timeout 以 Exception 掐断，控制器的 rescue 接不住，用户看到裸 500。
  # 所以在外面再套一道**总时长**闸刀，并伪装成 Faraday::TimeoutError，
  # 让各处已有的 `rescue Faraday::Error` 原样接住、显示「AI 暂时不可用」。
  def with_deadline(&)
    Timeout.timeout(REQUEST_TIMEOUT, &)
  rescue Timeout::Error
    raise Faraday::TimeoutError, "AI 服务 #{REQUEST_TIMEOUT} 秒没有响应"
  end

  def chat_once(system_prompt, user_prompt)
    context = RubyLLM.context do |config|
      config.openai_api_key = api_key
      config.openai_api_base = api_base
      # DeepSeek 只认 system 角色，不认 OpenAI 新的 developer 角色
      config.openai_use_system_role = true
      # 比 AI 接口的请求时限（见 config/initializers/rack_timeout.rb）早一点放弃，
      # 这样超时是普通异常、能被各处 rescue 成「AI 失败请重试」，而不是漏成裸 500。
      config.request_timeout = REQUEST_TIMEOUT
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

  # AI 返回的类型代码规整到 DOC_TYPES；不认识的一律 OTHER。
  def normalize_doc_type(type)
    code = type.to_s.upcase.strip
    DOC_TYPES.key?(code) ? code : 'OTHER'
  end

  # 纯文件名启发式分类（兜底）：按 DOC_TYPE_HINTS 顺序命中，全不中给 OTHER。
  def heuristic_doc_type(filename)
    DOC_TYPE_HINTS.each { |code, rx| return code if filename.to_s.match?(rx) }
    'OTHER'
  end

  # 从模型回复里抽出 JSON 对象；模型偶尔会加解释或代码块，取第一个 {...} 块解析。
  def parse_json(raw)
    json = raw.to_s[/\{.*\}/m]
    json ? JSON.parse(json) : { 'note' => raw.to_s }
  rescue JSON::ParserError
    { 'note' => raw.to_s }
  end
end
