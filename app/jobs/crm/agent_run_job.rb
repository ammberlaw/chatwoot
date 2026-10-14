# agent 跑一轮。放后台是因为它要连着调好几次工具、几十秒起步，
# 同步请求会被 rack-timeout 掐断（见 config/initializers/rack_timeout.rb）。
# 前端按会话的 status 轮询，RUNNING 就接着等。
class Crm::AgentRunJob < ApplicationJob
  queue_as :medium

  def perform(conversation_id, question)
    conversation = Crm::AgentConversation.find_by(id: conversation_id)
    return if conversation.nil?

    Current.account = conversation.account
    Crm::Agent::Runner.new(conversation: conversation).perform(question)
  ensure
    Current.account = nil
    # 兜底：Runner 正常走完会自己置状态，但它要是被 Sidekiq 杀掉（部署、OOM），
    # 会话会永远卡在 RUNNING、前端一直转圈。
    stuck = conversation&.reload
    stuck.update(status: 'FAILED', last_error: '这一轮被中断了，请重试') if stuck&.running?
  end
end
