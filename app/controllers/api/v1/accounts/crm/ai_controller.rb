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
    if result[:domain].present?
      result[:db_match] = company_db_match(result[:domain])
      stamp_bg_check(result)
    end
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
  # 背调留痕：查到的是已建档客户时，在客户上记一笔「什么时候背调的、结论是什么」。
  #
  # 原先这个接口是纯实时查、不落库，结果渲染完就没了。绩效考核里
  # 「客户信息完整（含公司背调）」这一项因此系统判不了（见 Crm::KpiSystemScorer）。
  # 只盖在当前用户自己名下的客户上——背调别人的客户不该算到别人的完整度里。
  def stamp_bg_check(result)
    return if result[:status].to_s == 'invalid' || result[:summary].blank?

    ids = Array(result.dig(:db_match, :visible)).filter_map { |c| c[:id] if c[:mine] }
    return if ids.empty?

    summary = result[:summary].to_s.truncate(2000)
    Current.account.crm_customers.where(id: ids).find_each do |customer|
      customer.update(bg_checked_at: Time.current, bg_summary: summary)
    end
  end

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
