# 邮件 AI 助手接口：写信 / 来信翻译 / 往来摘要（Crm::EmailAiService，DeepSeek）。
# 全部同步调用（生成 5~20 秒，前端转圈等待），不落库不建任务。
class Api::V1::Accounts::Crm::AiController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  rescue_from Crm::EmailAiService::NotConfigured do |e|
    render json: { message: e.message }, status: :unprocessable_entity
  end

  rescue_from RubyLLM::Error, Faraday::Error do |e|
    render json: { message: "AI 服务出错：#{e.message}" }, status: :bad_gateway
  end

  # 写信/回信：intent=中文意图，original=回复场景的原文引用（可选）。
  def compose
    intent = params[:intent].to_s.strip
    return render json: { message: '请先描述这封邮件要写什么' }, status: :unprocessable_entity if intent.blank?

    subject, body = service.compose(intent: intent, original: params[:original].presence)
    render json: { subject: subject, body: body }
  end

  # 整封翻译成中文：按邮件 id 取正文（优先纯文本，缺了剥 HTML）。
  # 可翻译范围＝本人/团队可见 ∪ 分发给我的（被分发人虽非 owner 也能看，自然也能翻译）。
  def translate
    email = readable_email(params[:email_id])
    return render json: { message: '邮件不存在或无权查看' }, status: :not_found unless email

    text = email.body.presence || ActionController::Base.helpers.strip_tags(email.body_html.to_s)
    subject, body = service.translate(subject: email.subject, body: text)
    render json: { subject: subject, body: body }
  end

  # 与某个对方地址的往来摘要：取可见范围内最近 30 封拼成记录送模型。
  def summarize
    address = params[:address].to_s.strip
    return render json: { message: '缺少对方邮箱地址' }, status: :unprocessable_entity if address.blank?

    emails = visible_emails
             .where('LOWER(from_address) = :addr OR to_address ILIKE :like', addr: address.downcase, like: "%#{address}%")
             .where.not(folder: 'DRAFT')
             .order(email_date: :desc).limit(30).to_a.reverse
    return render json: { message: '和这个地址还没有邮件往来' }, status: :unprocessable_entity if emails.empty?

    render json: { summary: service.summarize(transcript: build_transcript(address, emails)) }
  end

  # 对话式 AI 助手：一句话 → 意图路由（问数 / 背调 / 写邮件 / 闲聊），执行后返回自然语言答复。
  # 问数一律走当前用户的数据可见范围，不越权。
  def ask
    message = params[:message].to_s.strip
    return render json: { message: '请输入你的问题' }, status: :unprocessable_entity if message.blank?

    route = service.route_assistant(message: message)
    render json: execute_assistant(route, message)
  end

  # 客户「AI 下一步建议」：按客户最近往来 + 商机信息给一条可执行销售建议（同步，不落库）。
  def suggest
    customer = Current.account.crm_customers.find(params[:customer_id])
    emails = scope_by_mail_owner(customer.emails).where.not(folder: 'DRAFT')
                                                 .order(email_date: :desc).limit(12).to_a.reverse
    return render json: { message: '这个客户还没有邮件往来，无法生成建议' }, status: :unprocessable_entity if emails.empty?

    render json: { suggestion: service.suggest_next_step(transcript: suggest_transcript(customer, emails)) }
  end

  # 客户 AI 背调：输入邮箱/域名/网址→取企业域名→抓官网 + Apollo 概况，并顺带查库是否已建档。
  def company_lookup
    query = params[:query].to_s.strip
    return render json: { message: '请输入邮箱、公司域名或公司名' }, status: :unprocessable_entity if query.blank?

    result = Crm::CompanyLookupService.new(account: Current.account).call(query: query)
    result[:db_match] = company_db_match(result[:domain]) if result[:domain].present?
    render json: result
  end

  # 按公司名搜候选公司（Apollo），返回候选列表供前端挑一个再背调。
  def company_search
    name = params[:name].to_s.strip
    return render json: { message: '请输入公司名' }, status: :unprocessable_entity if name.blank?

    candidates = Crm::ApolloClient.new(account: Current.account).search_organizations(name: name)
    render json: { candidates: candidates }
  end

  private

  def check_authorization
    authorize(Crm::Email)
  end

  def service
    @service ||= Crm::EmailAiService.new(account: Current.account)
  end

  # 可见范围与邮件列表同口径（邮件私密）：系统管理员看全员；CRM 团队负责人看本团队；其余只看自己。
  def visible_emails
    scope_by_mail_owner(Current.account.crm_emails)
  end

  # 单封邮件的可读判定：本人/团队可见 ∪ 被分发给我的（分发接收人非 owner 也能看该邮件）。
  def readable_email(id)
    visible_emails.find_by(id: id) || distributed_to_me_email(id)
  end

  def distributed_to_me_email(id)
    return nil unless Current.account.crm_email_distributions.to_user(current_user.id).exists?(crm_email_id: id)

    Current.account.crm_emails.find_by(id: id)
  end

  # 该域名在系统里是否已建档：total 为全账户命中数（供去重预警），visible 仅返回当前用户可见范围的详情
  # （业务员只看自己/团队，其余只知数量不露客户名，守住数据可见性边界）。
  def company_db_match(domain)
    all = Current.account.crm_customers.where('LOWER(contact_email) LIKE ?', "%@#{domain.downcase}")
    ids = crm_visible_owner_ids
    visible = ids == :all ? all : all.where(account_owner_id: ids)
    {
      total: all.count,
      visible: visible.limit(10).map do |c|
        { id: c.id, name: c.name, owner: c.account_owner&.crm_display_name, mine: c.account_owner_id == Current.user&.id }
      end
    }
  end

  # ---- 对话式助手：按意图执行，返回 { kind:, reply:, data? } ----
  def execute_assistant(route, message)
    case route['intent']
    when 'query' then assistant_query(route)
    when 'background_check' then assistant_background(route)
    when 'compose' then assistant_compose(route, message)
    else
      { kind: 'chat', reply: route['answer'].presence || assistant_help }
    end
  rescue Crm::EmailAiService::NotConfigured => e
    { kind: 'chat', reply: e.message }
  end

  def assistant_help
    '我可以帮你：查数据（近30天新增客户 / 待跟进客户 / 在谈商机 / 本月订单额 / 我的待办）、写邮件、做客户背调。直接问我就行。'
  end

  # 问数：一律按当前用户的数据可见范围（管理员全部 / 主管团队 / 业务员本人）。
  def assistant_query(route)
    ids = crm_visible_owner_ids
    case route['metric']
    when 'new_customers'
      days = (route['days'] || 30).to_i.clamp(1, 365)
      n = owner_scoped(Current.account.crm_customers, :account_owner_id, ids).where('created_at >= ?', days.days.ago).count
      { kind: 'query', reply: "近 #{days} 天新增客户 #{n} 家。" }
    when 'pending_followups'
      n = owner_scoped(Current.account.crm_customers, :account_owner_id, ids)
          .where('next_follow_up_at <= ?', Time.current).count
      { kind: 'query', reply: "当前有 #{n} 个客户到了该跟进的时间。" }
    when 'open_opportunities'
      opps = owner_scoped(Current.account.crm_opportunities, :owner_id, ids).open_stages
      total = opps.sum { |o| o.amount_cny_micros || 0 }
      { kind: 'query', reply: "在谈商机 #{opps.count} 个，预估金额约 ¥#{delimited(total / 1_000_000)}（按今日牌价折算）。" }
    when 'orders_amount'
      scope = owner_scoped(Current.account.crm_sales_orders, :owner_id, ids).dealt.where(order_date: month_range(route['month']))
      total = scope.sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)).to_i
      { kind: 'query', reply: "#{month_label(route['month'])}成交订单 #{scope.count} 笔，金额约 ¥#{delimited(total / 1_000_000)}（折人民币）。" }
    when 'my_tasks'
      n = Current.account.crm_follow_up_tasks.where(assignee_id: current_user.id).where.not(status: 'DONE').count
      { kind: 'query', reply: "你有 #{n} 条待办跟进任务。" }
    else
      { kind: 'chat', reply: assistant_help }
    end
  end

  def assistant_background(route)
    q = route['target'].to_s.strip
    return { kind: 'chat', reply: '想背调哪家公司？告诉我对方邮箱、公司域名或公司名。' } if q.blank?

    result = Crm::CompanyLookupService.new(account: Current.account).call(query: q)
    result[:db_match] = company_db_match(result[:domain]) if result[:domain].present?
    { kind: 'background_check', reply: background_reply(q, result), data: result }
  end

  def assistant_compose(route, message)
    subject, body = service.compose(intent: route['compose_intent'].presence || message)
    { kind: 'compose', reply: '帮你拟了一封邮件草稿，可点「用此稿写信」直接发送或修改：', data: { subject: subject, body: body } }
  end

  def background_reply(query, result)
    case result[:status]
    when 'invalid' then "「#{query}」看起来不是有效的邮箱/域名/公司名，换个再试试。"
    when 'public_domain' then "#{result[:domain]} 是公共邮箱域名（如 gmail/qq），无法据此判断公司背景。"
    when 'no_site' then "找到域名 #{result[:domain]}，但没抓到可用的公司信息。"
    else background_ok_reply(result)
    end
  end

  LEGIT_LABEL = {
    'real' => '看起来是正常运营的真实公司', 'suspicious' => '信息可疑，建议谨慎核实', 'unknown' => '信息不足，难以判断'
  }.freeze

  def background_ok_reply(result)
    p = result[:profile] || {}
    parts = ["【#{p['company_name'].presence || result[:domain]}】"]
    parts << "主营：#{p['business']}" if p['business'].present?
    parts << (LEGIT_LABEL[p['legit']] || '—')
    parts << p['note'] if p['note'].present?
    hit = result[:db_match]&.dig(:total).to_i
    parts << "系统里已有 #{hit} 条同域名客户记录，注意查重" if hit.positive?
    parts.join('；')
  end

  # owner_field 按可见范围过滤；ids 为 :all 时不加过滤。
  def owner_scoped(relation, owner_field, ids)
    ids == :all ? relation : relation.where(owner_field => ids)
  end

  # order_date 是 timestamp，Date 的 all_month 会把当月最后一天整天切掉（见团队看板同名方法）。
  def month_range(month)
    date = parse_month(month)
    date.beginning_of_month.beginning_of_day..date.end_of_month.end_of_day
  end

  def month_label(month)
    base = parse_month(month)
    base.year == Time.zone.today.year && base.month == Time.zone.today.month ? '本月' : base.strftime('%Y年%-m月')
  end

  def parse_month(month)
    Date.strptime(month.to_s, '%Y-%m')
  rescue ArgumentError
    Time.zone.today
  end

  def delimited(number)
    ActiveSupport::NumberHelper.number_to_delimited(number.round)
  end

  # 客户建议用的 transcript：商机信息 + 最近往来。
  def suggest_transcript(customer, emails)
    "#{customer_opp_header(customer)}\n\n#{email_lines(emails)}"
  end

  def customer_opp_header(customer)
    opp = customer.opportunities.open_stages.order(updated_at: :desc).first ||
          customer.opportunities.order(updated_at: :desc).first
    header = "客户：#{customer.name}"
    return header unless opp

    amount = opp.amount_micros ? "#{opp.currency} #{(opp.amount_micros / 1_000_000.0).round}" : '未填'
    header += "\n当前商机：#{opp.name}｜阶段：#{opp.sales_stage}｜报价：#{amount}｜成交概率：#{opp.probability || '—'}%"
    header += "\n下一步（已记录）：#{opp.next_action}" if opp.next_action.present?
    header
  end

  def build_transcript(address, emails)
    "对方地址：#{address}\n\n#{email_lines(emails)}"
  end

  # 邮件往来拼成「时间/方向/主题/正文节选」多行文本，供 AI 摘要/建议。
  def email_lines(emails)
    emails.map do |e|
      dir = %w[SENT BULK].include?(e.folder) ? '我方→对方' : '对方→我方'
      date = e.email_date&.strftime('%Y-%m-%d') || '未知日期'
      body = e.body.to_s.gsub(/\s+/, ' ').strip[0, 500]
      "[#{date}] #{dir} 主题：#{e.subject}\n#{body}"
    end.join("\n\n")
  end
end
