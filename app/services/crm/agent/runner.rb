# CRM AI 助手跑一轮。
#
# 和「点一下做一件事」的那些 AI 功能不同（见 Crm::EmailAiService），这个是**带工具的**：
# 模型自己决定先查客户、再翻邮件、再起草，一轮里可能来回好几次。
#
# 规矩（用户定的）：**只读 + 出草稿**。工具里没有「发邮件」「提交 PI」这种动作，
# 想发也发不出去——能力上就不给，比在提示词里嘱咐它「别发」可靠得多。
class Crm::Agent::Runner
  class NotAllowed < StandardError; end

  # 一轮最多让它调几次工具。防的是模型钻进死循环（反复查同一个客户）把钱和时间烧光。
  MAX_TOOL_CALLS = 12

  pattr_initialize [:conversation!]

  def perform(question)
    scope = Crm::Agent::Scope.new(account: conversation.account, account_user: account_user)
    chat = build_chat(scope)
    answer = chat.ask(question).content.to_s.strip
    record_assistant(answer.presence || '（没有返回内容，请换个说法再问一次）')
  rescue RubyLLM::Error, Crm::EmailAiService::NotConfigured => e
    fail_with("AI 调用失败：#{e.message}")
  rescue StandardError => e
    Rails.logger.error("[crm_agent] 会话 #{conversation.id} 失败：#{e.class} #{e.message}")
    fail_with("出错了：#{e.message}")
  end

  private

  def account_user
    @account_user ||= conversation.account.account_users.find_by(user_id: conversation.user_id)
  end

  def settings = @settings ||= Crm::AiSetting.for_account(conversation.account)

  def build_chat(scope)
    context = RubyLLM.context do |config|
      config.openai_api_key = settings.api_key.presence || ENV.fetch('DEEPSEEK_API_KEY', nil)
      config.openai_api_base = settings.api_base.presence || Crm::EmailAiService::DEFAULT_API_BASE
      config.openai_use_system_role = true
      config.request_timeout = Crm::EmailAiService::REQUEST_TIMEOUT
    end
    chat = context.chat(model: settings.model.presence || Crm::EmailAiService::DEFAULT_MODEL,
                        provider: :openai, assume_model_exists: true)
    chat.with_instructions(system_prompt)
    tools(scope).each { |tool| chat.with_tool(tool) }
    replay_history(chat)
    attach_tool_recorder(chat)
    chat
  end

  def tools(scope)
    [Crm::Agent::Tools::FindCustomer, Crm::Agent::Tools::CustomerProfile,
     Crm::Agent::Tools::CustomerEmails, Crm::Agent::Tools::SearchProducts,
     Crm::Agent::Tools::DraftEmail, Crm::Agent::Tools::DraftPi].map { |klass| klass.new(scope) }
  end

  # 把之前的问答喂回去，不然每句话都是失忆的，用户得每次重报客户名。
  # 工具那几条不回放：它们是过程、很占长度，结论已经在 assistant 那条里了。
  def replay_history(chat)
    conversation.messages.where(role: %w[user assistant]).order(:id).each do |msg|
      chat.add_message(role: msg.role.to_sym, content: msg.content.to_s)
    end
  end

  # 把每次工具调用记下来摆给用户看。不摆的话 AI 说什么就是什么，
  # 没人判断得出它的结论是从哪条数据来的。
  def attach_tool_recorder(chat)
    calls = 0
    chat.before_tool_call do |call|
      calls += 1
      raise NotAllowed, '这一轮查得太多了，请把问题拆小一点再问' if calls > MAX_TOOL_CALLS

      conversation.messages.create!(role: 'tool', content: tool_label(call),
                                    meta: { tool: call.name.to_s, args: call.arguments })
    end
  end

  TOOL_LABELS = {
    'find_customer' => '查客户', 'customer_profile' => '看客户档案与订单',
    'customer_emails' => '调往来邮件', 'search_products' => '查产品档案',
    'draft_email' => '写邮件草稿', 'draft_pi' => '建 PI 草稿'
  }.freeze

  def tool_label(call)
    TOOL_LABELS.fetch(call.name.to_s, call.name.to_s)
  end

  def record_assistant(text)
    conversation.messages.create!(role: 'assistant', content: text)
    conversation.update!(status: 'IDLE', last_error: nil, title: conversation.title.presence || conversation.title_from_first_question)
    text
  end

  def fail_with(message)
    conversation.messages.create!(role: 'assistant', content: message)
    conversation.update!(status: 'FAILED', last_error: message)
    message
  end

  def system_prompt
    <<~PROMPT
      你是 wintouchspace 这套外贸 CRM 里的助手，帮业务员处理客户、往来邮件、报价和 PI。

      硬规矩：
      1. 只用工具查到的真实数据回答。查不到就说查不到，**绝对不要编**客户、订单、价格或邮件内容。
      2. 你**不能发邮件、不能提交 PI**。写好的邮件只能存草稿，PI 只能建草稿，
         最后一定要提醒用户自己去核对并手动发送/导出。
      3. 数字（价格/数量/交期）**用户明确给了就照用户的办，直接做，不要反问**——
         档案里的售价只是参考价，定制件、不同年用量的报价本来就不一样。
         用户没给、工具也查不到的数字，才说「这个需要你确认」，绝不自己编一个。
         要是用户给的数和档案差很多，先把事做了，再在最后用一句话提一下差异就行。
      4. 用户说中文就用中文回答；要写给客户的邮件正文，按客户所在国家用对应语言写。
      5. 回答简短直接，别客套。要列清单就列清单。

      #{customer_hint}
    PROMPT
  end

  # 从客户详情面板发起的对话，默认就在聊这个客户，省得用户每句话都报一遍名字。
  def customer_hint
    return '' if conversation.crm_customer.blank?

    "当前对话默认是在谈客户「#{conversation.crm_customer.name}」（客户ID #{conversation.crm_customer_id}），" \
      '用户没有特别指明别的客户时就用它。'
  end
end
