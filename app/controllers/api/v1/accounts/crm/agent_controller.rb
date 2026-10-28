# CRM AI 助手。
#
# 跑一轮几十秒且要连调几次工具，所以 create_message 只把任务丢进后台就返回，
# 前端按 show 的 status 轮询（RUNNING 就接着等）。
class Api::V1::Accounts::Crm::AgentController < Api::V1::Accounts::Crm::BaseController
  # 直接发给助手的图/文件上限。超了没必要收进对象存储再读一遍：
  # 视觉模型按图算 token，大 PDF 抽出来的正文也塞不进一轮对话（见 AgentRunJob::MAX_DOC_CHARS）。
  MAX_UPLOAD_BYTES = 15.megabytes

  # AI 助手不走 CRM 总门禁。球挂在全局外壳上，MES、ERP 哪一页都跟着走，车间和财务
  # 同样在 AI 名单里（生产名单 40 人中 25 人没有 CRM 角色），但 BaseController 的
  # ensure_crm_access 先于名单检查把他们挡掉——于是球看得见、点得开，一问就弹
  # 「无权访问 CRM」（2026-10-28 生产反馈，车间问的是「生产怎么做退料单」，
  # 这类功能导航类问题根本不碰 CRM 数据）。
  #
  # 放开这道门不等于放开数据：取数全部经 Crm::Agent::Scope，没有 CRM 角色的人
  # team_visible_owner_ids 会收敛成 [本人]，客户/订单/邮件只剩自己归属的 + 公海，
  # 跟他在 CRM 页面里能看到的一模一样。能不能用这个功能，由 ensure_allowed!
  # （管理员 + AI 名单）这一道说了算。
  skip_before_action :ensure_crm_access

  before_action :ensure_allowed!
  before_action :fetch_conversation, only: [:show, :create_message, :destroy]

  def index
    @conversations = Current.account.crm_agent_conversations
                            .where(user_id: current_user.id).recent_first.limit(30)
  end

  def show; end

  def create
    @conversation = Current.account.crm_agent_conversations.create!(
      user_id: current_user.id, crm_customer_id: customer_id_param, status: 'IDLE'
    )
    render 'api/v1/accounts/crm/agent/show'
  end

  # 提问：先把问话落库（前端立刻能显示出去），再丢后台跑。
  def create_message
    question = params[:content].to_s.strip
    file = params[:attachment]
    # 只发附件不打字是常见用法（展会上拍一张规格表、把客户刚发来的 PI 甩给它），
    # 所以有附件时允许正文为空。
    question = default_question(file) if question.blank? && file.present?
    blocker = message_blocker(question, file)
    return render json: { error: blocker }, status: :unprocessable_entity if blocker

    msg = @conversation.messages.create!(role: 'user', content: question)
    msg.attachment.attach(file) if file.present?
    @conversation.update!(status: 'RUNNING', last_error: nil)
    Crm::AgentRunJob.perform_later(@conversation.id, question, page_context_param, msg.id)
    render 'api/v1/accounts/crm/agent/show'
  end

  def destroy
    @conversation.destroy!
    head :ok
  end

  private

  # 发不出去的理由（给用户看的人话）。nil＝可以发。
  def message_blocker(question, file)
    return '请先输入问题' if question.blank?
    return "文件太大了（上限 #{MAX_UPLOAD_BYTES / 1.megabyte}MB）" if file.present? && file.size.to_i > MAX_UPLOAD_BYTES

    '上一轮还在跑，等它答完再问' if @conversation.running?
  end

  # 只丢个附件、一个字没打时替他问的那句。图和文档要分开说——
  # 对着一份 PI 说「把图里的内容读出来」，模型会跟着这个说法答得很怪。
  def default_question(file)
    return '看看这张图，把里面的内容读出来。' if file.content_type.to_s.start_with?('image/')

    "读一下这个文件「#{file.original_filename}」，把里面的内容整理出来。"
  end

  # 用户提问时正开着哪一页。只收两样：路由名和页面上那个筛选词/单号。
  # 白名单式地收，不照单全收前端塞来的东西——这串会被拼进提示词，
  # 任人往里塞自由文本等于给提示词注入开后门。
  def page_context_param
    ctx = params[:page_context]
    return nil if ctx.blank?

    route = ctx[:route].to_s[0, 60]
    return nil if route.blank? || !route.match?(/\A[a-z0-9_]+\z/)

    { 'route' => route, 'subject' => ctx[:subject].to_s.strip[0, 60].presence }.compact
  end

  def customer_id_param
    id = params[:crm_customer_id].presence
    # 客户也要过可见范围：不能借 agent 把别人私海的客户挂成对话上下文。
    id && visible_customers.find_by(id: id)&.id
  end

  # 附件连 blob 一起预载：show 是每 2 秒轮询一次的，不预载每条消息都要各查一次
  # attachment + blob，一轮对话二三十条就是几十次往返。
  def fetch_conversation
    @conversation = Current.account.crm_agent_conversations
                           .where(user_id: current_user.id)
                           .includes(messages: { attachment_attachment: :blob })
                           .find(params[:id])
  end

  def ensure_allowed!
    return if Crm::AiSetting.agent_allowed?(Current.account, Current.account_user)

    render json: { error: 'AI 助手还没开放给你，请让管理员在「AI 设置」里添加' }, status: :forbidden
  end
end
