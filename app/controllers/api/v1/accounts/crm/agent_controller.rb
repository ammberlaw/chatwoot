# CRM AI 助手。
#
# 跑一轮几十秒且要连调几次工具，所以 create_message 只把任务丢进后台就返回，
# 前端按 show 的 status 轮询（RUNNING 就接着等）。
class Api::V1::Accounts::Crm::AgentController < Api::V1::Accounts::Crm::BaseController
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
    return render json: { error: '请先输入问题' }, status: :unprocessable_entity if question.blank?
    return render json: { error: '上一轮还在跑，等它答完再问' }, status: :unprocessable_entity if @conversation.running?

    @conversation.messages.create!(role: 'user', content: question)
    @conversation.update!(status: 'RUNNING', last_error: nil)
    Crm::AgentRunJob.perform_later(@conversation.id, question, page_context_param)
    render 'api/v1/accounts/crm/agent/show'
  end

  def destroy
    @conversation.destroy!
    head :ok
  end

  private

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

  def fetch_conversation
    @conversation = Current.account.crm_agent_conversations
                           .where(user_id: current_user.id).find(params[:id])
  end

  def ensure_allowed!
    return if Crm::AiSetting.agent_allowed?(Current.account, Current.account_user)

    render json: { error: 'AI 助手还没开放给你，请让管理员在「AI 设置」里添加' }, status: :forbidden
  end
end
