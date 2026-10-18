# 记一条跟进记录，顺手把下次跟进时间定下来。
#
# 之前 agent 是纯只读的：业务员打完电话跟它说完情况，还得自己回客户页再敲一遍，
# 那一步十次有三次没人做——客户的「上次跟进时间」就停在那，接着被公海回收。
#
# 写的是真记录不是草稿，所以：
# · source 记成 AI，时间线上带 AI 徽标——让人一眼看出这条是机器代录的，可信度和手写的不一样；
# · 只写**用户说过的内容**，模型不许自己补结论（提示词里管着）；
# · 记录建完会自动刷新客户的「上次跟进时间」（模型 after_create 干的，别在这儿重复写）。
class Crm::Agent::Tools::LogFollowUp < Crm::Agent::Tools::Base
  description '把这次跟进记进客户的跟进记录里（电话/微信/会面聊完让我记一下就用这个），可以同时定下次跟进时间、建一条待办。只记用户真说过的内容，不要自己编客户说了什么。'
  param :customer_id, type: 'integer', desc: '客户ID'
  param :title, desc: '一句话标题，例如「电话回访：确认样机测试结果」'
  param :body, desc: '聊了什么、客户什么态度、下一步做什么', required: false
  param :way, desc: '沟通方式：PHONE 电话｜WECHAT 微信｜WHATSAPP｜MEETING 会面｜EMAIL 邮件', required: false
  param :result, desc: '结果：INTERESTED 有意向｜WAITING_CUSTOMER 等客户回话｜WAITING_INTERNAL 等内部处理｜INVALID 无效', required: false
  param :next_follow_up_on, desc: '下次跟进日期，写成 2026-10-24；给了就同时更新客户的「下次跟进时间」', required: false
  param :task_title, desc: '要建的待办标题；给了就在跟进任务里建一条派给自己，到期日用 next_follow_up_on', required: false

  # 必填两个显式写出来（RubyLLM 会替我们校验缺参），其余塞 opts：
  # 可选项有五个，全列出来会撞 rubocop 的参数个数上限。
  def execute(customer_id:, title:, **opts)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户，没法记跟进。" if customer.nil?
    return '标题不能为空，写一句话说明这次跟进干了什么。' if title.to_s.strip.blank?

    note = create_note(customer, title, opts)
    due = opts[:next_follow_up_on]
    extras = [schedule_next(customer, due), create_task(customer, opts[:task_title], due)].compact_blank
    scope.record_artifact(kind: 'customer', id: customer.id, customer_id: customer.id,
                          label: "跟进记录：#{title.to_s.strip.truncate(20)}")
    done_text(customer, note, extras)
  end

  private

  def create_note(customer, title, opts)
    Audited.audit_class.as_user(scope.user) do
      scope.account.crm_follow_up_notes.create!(
        crm_customer_id: customer.id, owner_id: scope.user_id, source: 'AI',
        title: title.to_s.strip, body: opts[:body].to_s.presence,
        follow_up_method: enum_or_nil(opts[:way], Crm::FollowUpNote::FOLLOW_UP_METHODS),
        result_tag: enum_or_nil(opts[:result], Crm::FollowUpNote::RESULT_TAGS)
      )
    end
  end

  # 日期解析失败就当没给：定错下次跟进时间比不定更坏（人会以为已经安排上了）。
  def schedule_next(customer, value)
    date = parse_date(value)
    return nil if date.nil?

    Audited.audit_class.as_user(scope.user) { customer.update!(next_follow_up_at: date) }
    "下次跟进时间已设为 #{date}"
  end

  def create_task(customer, task_title, due_on)
    return nil if task_title.to_s.strip.blank?

    task = scope.account.crm_follow_up_tasks.create!(
      crm_customer_id: customer.id, assignee_id: scope.user_id, status: 'TODO',
      title: task_title.to_s.strip, due_at: parse_date(due_on)
    )
    "待办已建（#{task.title}#{task.due_at ? "，到期 #{day(task.due_at)}" : ''}）"
  end

  def done_text(customer, note, extras)
    head = ["已记进 #{customer.name} 的跟进记录（#{day(note.created_at)}｜#{note.title}）", *extras].join('；')
    "#{head}。客户的「上次跟进时间」已跟着刷新。"
  end

  # 模型经常直接传中文（「电话」「有意向」），认不出来就只是少一个标签、不该让整条记录失败。
  WAY_ALIASES = { '电话' => 'PHONE', '打电话' => 'PHONE', '微信' => 'WECHAT', '邮件' => 'EMAIL',
                  '邮箱' => 'EMAIL', '面谈' => 'MEETING', '会面' => 'MEETING', '拜访' => 'MEETING',
                  '展会' => 'MEETING' }.freeze
  RESULT_ALIASES = { '有意向' => 'INTERESTED', '感兴趣' => 'INTERESTED', '等客户' => 'WAITING_CUSTOMER',
                     '等客户回话' => 'WAITING_CUSTOMER', '等内部' => 'WAITING_INTERNAL',
                     '等内部处理' => 'WAITING_INTERNAL', '无效' => 'INVALID' }.freeze

  def enum_or_nil(value, allowed)
    key = value.to_s.strip
    upper = key.upcase
    return upper if allowed.include?(upper)

    aliases = allowed.equal?(Crm::FollowUpNote::FOLLOW_UP_METHODS) ? WAY_ALIASES : RESULT_ALIASES
    aliases[key]
  end

  def parse_date(value)
    return nil if value.to_s.strip.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
