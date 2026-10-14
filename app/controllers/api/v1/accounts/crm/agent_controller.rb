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
    Crm::AgentRunJob.perform_later(@conversation.id, question)
    render 'api/v1/accounts/crm/agent/show'
  end

  def destroy
    @conversation.destroy!
    head :ok
  end

  private

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
