# 记住一件关于这个人的事，下次对话还算数。
#
# 为什么要有：现在每开一个新对话都是白纸。用户说过「邮件写短点」「这家一律报 FOB」
# 「别叫我 Dear Sir」，下一轮全忘，他得反复教同一件事——日常用的人最烦这个。
#
# 只记**关于这个人怎么用系统**的事（偏好、口径、纠正），不记业务数据：
# 客户的价格、订单状态都在库里查得到，抄进记忆只会过期，还会和真数据打架。
class Crm::Agent::Tools::Remember < Crm::Agent::Tools::Base
  description '记住用户的一条偏好或纠正，以后每次对话都带着。' \
              '用户说「以后都…」「记住…」「不要再…」「我习惯…」时用；' \
              '他纠正你的做法、或顺口讲了他的习惯（哪怕没说「记住」），也该记——' \
              '记完一句话告诉他记了什么就行。' \
              '只记他怎么用系统的偏好，**不要记业务数据**（价格、订单状态、客户信息都该现查）。'
  param :content, desc: '一句话，站在他的角度写，例如「写邮件要简短，不超过 5 句」「不要用 Dear Sir，用具体人名」'
  param :company_wide, type: 'boolean',
                       desc: '这条是不是全公司的规矩（「我们公司一律…」「以后大家都…」）。' \
                             '默认 false＝只对他自己算数。只有管理员能立公司规矩，不是就会被拒。',
                       required: false

  # 立全公司的规矩＝替所有人改口径，和改配置一个性质，所以照管理面的口径收：
  # 系统管理员 / 副管理员 / CRM 负责人。业务员只能记自己的。
  def execute(content:, company_wide: false)
    text = content.to_s.strip
    return '要记的内容是空的。' if text.blank?
    return refusal if company_wide && !may_set_company_rule?

    row = Crm::AgentMemory.remember!(account: scope.account, user_id: scope.user_id,
                                     content: text, conversation_id: conversation_id,
                                     account_wide: company_wide)
    return '这条已经记过了，没重复记。' if row.nil? || row.created_at < 1.minute.ago

    prefix = row.account_wide? ? '记成了全公司的规矩' : '记住了'
    "#{prefix}：#{row.content}"
  end

  private

  def refusal
    '这条要立成全公司的规矩，得管理员来说——我先没记。' \
      '你要是只想让它对你自己算数，跟我说一声我就记下。'
  end

  def may_set_company_rule?
    au = scope.account_user
    return false if au.blank?

    au.administrator? || au.crm_deputy_admin? || au.crm_manager?
  end

  # Base 不一定持有会话，拿不到就留空——记忆本身不依赖它，只是便于回溯来源。
  def conversation_id = scope.try(:conversation_id)
end
