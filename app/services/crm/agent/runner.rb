# CRM AI 助手跑一轮。
#
# 和「点一下做一件事」的那些 AI 功能不同（见 Crm::EmailAiService），这个是**带工具的**：
# 模型自己决定先查客户、再翻邮件、再起草，一轮里可能来回好几次。
#
# 规矩（用户定的）：**只读 + 出草稿**。工具里没有「发邮件」「提交 PI」这种动作，
# 想发也发不出去——能力上就不给，比在提示词里嘱咐它「别发」可靠得多。
class Crm::Agent::Runner
  pattr_initialize [:conversation!]

  # 流式落库的节流间隔（秒）。模型吐 token 很密（实测 190 字 112 个 chunk），
  # 每个 chunk 写一次库就是每秒几十条 UPDATE，而前端 2 秒才拉一次，写得再密也看不见。
  #
  # 为什么是 0.5 而不是更大：DeepSeek 吐字极快（190 字 ≈ 0.2 秒），间隔给大了整段话
  # 吐完都还没到第一次落库，流式等于没开。真正慢的是首字延迟和工具调用来回——
  # 那两段屏幕上有工具进度条顶着，不空。换成吐字慢的模型（AI 设置里可换）这里才真正发力。
  PARTIAL_FLUSH_INTERVAL = 0.5

  # 一轮整体的时限。agent 要连调好几次工具，比单次问答慢得多，但不能没有上限：
  # 模型侧挂住时（2026-10-15 DeepSeek 故障，连接活着、只发心跳不吐 token），
  # 没有这道闸刀，sidekiq 的 worker 会被一直占着，后面排队的任务全都跑不动。
  RUN_DEADLINE = 180

  def perform(question)
    Timeout.timeout(RUN_DEADLINE) { run(question) }
  rescue Timeout::Error
    fail_with("AI 服务 #{RUN_DEADLINE} 秒没有响应，可能是模型侧暂时不可用，稍后再试。")
  rescue RubyLLM::Error, Faraday::Error, Crm::EmailAiService::NotConfigured => e
    fail_with("AI 调用失败：#{e.message}")
  rescue StandardError => e
    Rails.logger.error("[crm_agent] 会话 #{conversation.id} 失败：#{e.class} #{e.message}")
    fail_with("出错了：#{e.message}")
  end

  private

  def run(question)
    @started_at = Time.current
    @chat = build_chat(scope)
    answer = ask_streaming(@chat, question)
    record_assistant(answer.presence || '（没有返回内容，请换个说法再问一次）')
  end

  # 用量：整轮合计（含中间几次工具调用的来回），挂在 assistant 那条上。
  # token 数由模型侧返回，拿不到就留空——不自己估，估出来的数拿去算成本还不如没有。
  def usage_attrs
    {
      input_tokens: token_sum(:input_tokens),
      output_tokens: token_sum(:output_tokens),
      duration_ms: @started_at && ((Time.current - @started_at) * 1000).round
    }
  end

  def token_sum(field)
    rows = @chat&.messages.to_a.filter_map { |m| m.public_send(field) if m.respond_to?(field) }
    rows.sum if rows.any?
  end

  # 边吐边落库。工具调用的进度本来就一条条摆出来了，但最后那段正文以前是整段落地——
  # 模型写五百字要十几秒，这十几秒屏幕上只有「正在查…」，人会以为卡死了。
  # 流式下前端（2 秒一轮询）看到的是文字在长。
  #
  # 刻意不上 WebSocket：轮询已经在跑，把增量写进同一条消息就够了，省一套推送通道。
  def ask_streaming(chat, question)
    buffer = +''
    last_flush = Time.current
    chat.ask(question) do |chunk|
      buffer << chunk.content.to_s
      next if Time.current - last_flush < PARTIAL_FLUSH_INTERVAL

      last_flush = Time.current
      flush_partial(buffer)
    end.content.to_s.strip
  end

  # 落一条「还没写完」的 assistant 消息，反复更新它；最后由 record_assistant 定稿同一条，
  # 所以用户不会看到半截和成品两条。
  def flush_partial(buffer)
    text = buffer.strip
    return if text.empty?

    @partial ||= conversation.messages.create!(role: 'assistant', content: '', meta: { streaming: true })
    # update_columns：这条每秒要写一次，不需要验证和回调。
    @partial.update_columns(content: text, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def scope
    @scope ||= Crm::Agent::Scope.new(account: conversation.account, account_user: account_user)
  end

  def account_user
    @account_user ||= conversation.account.account_users.find_by(user_id: conversation.user_id)
  end

  def settings = @settings ||= Crm::AiSetting.for_account(conversation.account)

  # 没 key 就别去撞上游了：拿回来的是一串英文鉴权错误（「Authentication Fails…」），
  # 管理员看不出是没配还是配错。NotConfigured 会被 perform 翻译成人话。
  def api_key!
    key = settings.api_key.presence || ENV.fetch('DEEPSEEK_API_KEY', nil).presence
    return key if key.present?

    raise Crm::EmailAiService::NotConfigured, 'AI 还没配置：请到「AI 设置」填上 API Key'
  end

  def llm_context(api_key)
    RubyLLM.context do |config|
      config.openai_api_key = api_key
      config.openai_api_base = settings.api_base.presence || Crm::EmailAiService::DEFAULT_API_BASE
      config.openai_use_system_role = true
      config.request_timeout = Crm::EmailAiService::REQUEST_TIMEOUT
    end
  end

  def build_chat(scope)
    chat = llm_context(api_key!).chat(
      model: settings.model.presence || Crm::EmailAiService::DEFAULT_MODEL,
      provider: :openai, assume_model_exists: true
    )
    chat.with_instructions(Crm::Agent::Prompt.build(conversation))
    tools(scope).each { |tool| chat.with_tool(tool) }
    replay_history(chat)
    attach_tool_recorder(chat)
    chat
  end

  TOOL_CLASSES = [
    Crm::Agent::Tools::FindCustomer, Crm::Agent::Tools::CustomerProfile,
    Crm::Agent::Tools::CustomerEmails, Crm::Agent::Tools::SearchProducts,
    Crm::Agent::Tools::QuoteHistory, Crm::Agent::Tools::StockLookup,
    Crm::Agent::Tools::OrderProgress, Crm::Agent::Tools::MyNumbers,
    Crm::Agent::Tools::MyWorklist, Crm::Agent::Tools::DormantCustomers, Crm::Agent::Tools::CompanyLookup,
    Crm::Agent::Tools::DraftEmail, Crm::Agent::Tools::DraftPi,
    Crm::Agent::Tools::FollowUpNotes, Crm::Agent::Tools::Quotes,
    Crm::Agent::Tools::MyTargets, Crm::Agent::Tools::Shipments,
    Crm::Agent::Tools::ProductDocs, Crm::Agent::Tools::LogFollowUp,
    Crm::Agent::Tools::CreateCustomer, Crm::Agent::Tools::DraftQuote,
    Crm::Agent::Tools::CreateOpportunity, Crm::Agent::Tools::ReadAttachment,
    # 「这单为什么卡着」+「这是 bug，帮我报上去」。诊断只读、事实全来自
    # Mes::DocDiagnosis，模型只负责把结果说成人话。
    Crm::Agent::Tools::DiagnoseDocument, Crm::Agent::Tools::ReportIssue
  ].freeze

  def tools(scope)
    TOOL_CLASSES.map { |klass| klass.new(scope) }
  end

  # 回放多少轮。一问一答算两条，所以 16 条约等于最近 8 轮。
  # 不回放全部：历史是每轮**原样重发**给模型的，聊到第 20 轮时每次请求都在重付前面所有内容的钱，
  # 而真正有用的上下文（在聊哪个客户、刚才给了什么价）基本都在最近几轮里。
  REPLAY_MESSAGES = 16
  # 更早的内容压成一句话带过去，省得「上次说的那个价」彻底失忆。
  OLD_SUMMARY_CLIP = 400

  # 把之前的问答喂回去，不然每句话都是失忆的，用户得每次重报客户名。
  # 工具那几条不回放：它们是过程、很占长度，结论已经在 assistant 那条里了。
  def replay_history(chat)
    rows = conversation.messages.where(role: %w[user assistant]).order(:id).to_a
    recent = rows.last(REPLAY_MESSAGES)
    older = rows[0...-recent.size]

    add_old_summary(chat, older)
    recent.each { |msg| chat.add_message(role: msg.role.to_sym, content: msg.content.to_s) }
  end

  # 被截掉的那段只留「用户问过什么」——他问的话短、信息密度高（客户名、型号、价格都在里面），
  # 而早先的长篇回答再塞回去就白花钱了。
  def add_old_summary(chat, older)
    return if older.blank?

    asked = older.select { |m| m.role == 'user' }.map { |m| m.content.to_s.squish }.join('；')
    return if asked.blank?

    chat.add_message(
      role: :user,
      content: "（这轮对话更早的部分已省略，之前问过：#{asked.truncate(OLD_SUMMARY_CLIP)}）"
    )
  end

  # 把每次工具调用记下来摆给用户看。不摆的话 AI 说什么就是什么，
  # 没人判断得出它的结论是从哪条数据来的。
  # 次数上限由 Crm::Agent::Scope 管（超了工具回一句话让模型收口，不抛异常），
  # 这里只负责把调用记下来摆给用户看。超限之后那几次照样记，但标出来——
  # 不然用户看到「查客户」却没结果，会以为是查漏了。
  def attach_tool_recorder(chat)
    recorder = Crm::Agent::StepRecorder.new(conversation: conversation, label: method(:tool_label))
    chat.before_tool_call do |call|
      recorder.start(call, note: scope.budget_exhausted? ? '已达本轮查询上限，改用已查到的信息作答' : nil)
    end
    chat.after_tool_result { recorder.finish }
  end

  TOOL_LABELS = {
    'find_customer' => '查客户', 'customer_profile' => '看客户档案与订单',
    'customer_emails' => '调往来邮件', 'search_products' => '查产品档案',
    'quote_history' => '翻历史报价', 'stock_lookup' => '查实时库存',
    'order_progress' => '查订单生产进度', 'my_numbers' => '算工作台数字',
    'my_worklist' => '列待办清单', 'dormant_customers' => '查沉睡客户',
    'company_lookup' => '做客户背调',
    'draft_email' => '写邮件草稿', 'draft_pi' => '建 PI 草稿',
    'follow_up_notes' => '翻跟进记录', 'quotes' => '查报价单状态',
    'my_targets' => '算目标与提成', 'shipments' => '查出货情况',
    'product_docs' => '翻产品资料', 'log_follow_up' => '记跟进记录',
    'create_customer' => '建客户档案', 'draft_quote' => '建报价单草稿',
    'create_opportunity' => '建商机', 'read_attachment' => '读邮件附件',
    'diagnose_document' => '诊断这张单卡在哪', 'report_issue' => '把问题提交给管理员'
  }.freeze

  def tool_label(call)
    TOOL_LABELS.fetch(call.name.to_s, call.name.to_s)
  end

  def record_assistant(text)
    write_answer(text)
    conversation.update!(status: 'IDLE', last_error: nil, title: conversation.title.presence || conversation.title_from_first_question)
    text
  end

  # 有流式占位就定稿那一条（顺便把 streaming 标记抹掉），否则新建。
  def write_answer(text)
    attrs = { content: text, meta: assistant_meta }.merge(usage_attrs)
    if @partial
      @partial.update!(attrs)
    else
      conversation.messages.create!(attrs.merge(role: 'assistant'))
    end
  end

  # 这一轮建出来的草稿挂到回答上，前端摆成能点的入口。
  # 半路失败也挂：草稿可能已经建好了，不给入口反而更难找。
  def assistant_meta
    list = @scope&.artifacts
    list.present? ? { artifacts: list } : {}
  end

  # 半路挂了也把已经吐出来的那半截留着：模型常常先写完有用的部分才超时，
  # 整条抹掉换一句「失败了」反而更糟。
  def fail_with(message)
    partial = @partial&.content.to_s.strip
    text = partial.present? ? "#{partial}\n\n（#{message}）" : message
    write_answer(text)
    conversation.update!(status: 'FAILED', last_error: message)
    message
  end
end
