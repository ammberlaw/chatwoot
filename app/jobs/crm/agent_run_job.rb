# agent 跑一轮。放后台是因为它要连着调好几次工具、几十秒起步，
# 同步请求会被 rack-timeout 掐断（见 config/initializers/rack_timeout.rb）。
# 前端按会话的 status 轮询，RUNNING 就接着等。
class Crm::AgentRunJob < ApplicationJob
  queue_as :medium

  # page_context：用户提问那一刻正开着哪一页（见 Crm::Agent::Prompt#page_hint）。
  # 走参数不走数据库列：它只对这一轮有意义，下一句话人可能已经翻到别的页了，
  # 存进会话反而会拿过期的页面去误导模型。
  def perform(conversation_id, question, page_context = nil)
    conversation = Crm::AgentConversation.find_by(id: conversation_id)
    return if conversation.nil?

    Current.account = conversation.account
    Crm::Agent::Runner.new(conversation: conversation, page_context: page_context).perform(question)
  ensure
    Current.account = nil
    # 兜底：Runner 正常走完会自己置状态，但它要是被 Sidekiq 杀掉（部署、OOM），
    # 会话会永远卡在 RUNNING、前端一直转圈。
    stuck = conversation&.reload
    stuck.update(status: 'FAILED', last_error: '这一轮被中断了，请重试') if stuck&.running?
  end
end
