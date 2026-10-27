# 记住一件关于这个人的事，下次对话还算数。
#
# 为什么要有：现在每开一个新对话都是白纸。用户说过「邮件写短点」「这家一律报 FOB」
# 「别叫我 Dear Sir」，下一轮全忘，他得反复教同一件事——日常用的人最烦这个。
#
# 只记**关于这个人怎么用系统**的事（偏好、口径、纠正），不记业务数据：
# 客户的价格、订单状态都在库里查得到，抄进记忆只会过期，还会和真数据打架。
class Crm::Agent::Tools::Remember < Crm::Agent::Tools::Base
  description '记住用户的一条偏好或纠正，以后每次对话都带着。' \
              '用户说「以后都…」「记住…」「不要再…」「我习惯…」时用。' \
              '只记他怎么用系统的偏好，**不要记业务数据**（价格、订单状态、客户信息都该现查）。'
  param :content, desc: '一句话，站在他的角度写，例如「写邮件要简短，不超过 5 句」「不要用 Dear Sir，用具体人名」'

  def execute(content:)
    text = content.to_s.strip
    return '要记的内容是空的。' if text.blank?

    row = Crm::AgentMemory.remember!(account: scope.account, user_id: scope.user_id,
                                     content: text, conversation_id: conversation_id)
    return '这条已经记过了，没重复记。' if row.nil? || row.created_at < 1.minute.ago

    "记住了：#{row.content}"
  end

  private

  # Base 不一定持有会话，拿不到就留空——记忆本身不依赖它，只是便于回溯来源。
  def conversation_id = scope.try(:conversation_id)
end
