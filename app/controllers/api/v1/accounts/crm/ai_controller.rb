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
  def translate
    email = visible_emails.find(params[:email_id])
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

  # 可见范围与邮件列表同口径：管理员全员 / 主管团队 / 业务员自己。
  def visible_emails
    scope_by_owner(Current.account.crm_emails)
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
        { id: c.id, name: c.name, owner: c.account_owner&.name, mine: c.account_owner_id == Current.user&.id }
      end
    }
  end

  def build_transcript(address, emails)
    lines = emails.map do |e|
      dir = %w[SENT BULK].include?(e.folder) ? '我方→对方' : '对方→我方'
      date = e.email_date&.strftime('%Y-%m-%d') || '未知日期'
      body = e.body.to_s.gsub(/\s+/, ' ').strip[0, 500]
      "[#{date}] #{dir} 主题：#{e.subject}\n#{body}"
    end
    "对方地址：#{address}\n\n#{lines.join("\n\n")}"
  end
end
