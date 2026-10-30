# AI 助手的每日体检：把昨天的对话跑一遍，机检出「它在哪儿掉链子」。
#
# 为什么要机检而不是让模型读一遍打分：模型给「这个回答好不好」打分是主观的、每天标准还会飘。
# 下面这些信号全是计数和字符串匹配，同样的对话今天明天算出来一个样，可以逐日比。
# 模型只在后面一步用——把机检出的异常对话读一遍，写成人话的诊断（见 Crm::Agent::QualityDiagnosis）。
#
# 2026-10-30 手工翻了三天对话，这八个信号是那次真正指向问题的那几个：
# 平均轮次只有 1.6（问一次就走）、一轮调 21 次工具、同一工具换着词调 4 次、
# 最后一条回过头要「邮件ID」、用户被逼到说「不要纠结系统有没有」。
class Crm::Agent::QualityAudit
  # 一轮调超过这么多次工具，基本就是在原地打转了（正常办完一件事 3~6 次）。
  FLAILING_TOOL_CALLS = 12
  # 同一个工具换着参数调这么多次，是在反复试关键词。
  REPEAT_SAME_TOOL = 3

  # 工具回了这些话＝这条路走不通。命中不代表助手有错（有时确实没有），
  # 但**连着撞墙还不换路**就是问题，所以只统计不定性。
  DEAD_END_HINTS = %w[没找到 查不到 看不到 不在你的可见范围 没有可用 不是有效].freeze

  # 最后一条回答里出现这些＝它把问题丢回给用户了。
  # 用户本来就是来问它的，一轮结束还在要信息，这一轮基本是白跑。
  ASK_BACK_HINTS = %w[报给我 发我 告诉我 请提供 是哪一个 哪一家 给我一个 你能给].freeze

  # 用户这么说＝它上一轮答错了或者轴住了。这是最硬的负反馈，比任何推断都准。
  USER_CORRECTION_HINTS = %w[不对 不是这个 不要纠结 我说的是 你搞错 不是我要的 重新].freeze

  # 拿 0 或 "x" 这种占位值去调工具＝明知参数没有也要试一下，纯浪费额度。
  PLACEHOLDER_ARGS = ['"email_id":0', '"email_id": 0', '"customer_id":0', '"customer_id": 0',
                      '"body":"x"', '"body": "x"'].freeze

  Finding = Struct.new(:conversation_id, :user_name, :question, :signals, :tool_calls, :turns,
                       keyword_init: true)

  def initialize(account:, date: Date.yesterday)
    @account = account
    @date = date
  end

  # 返回 { date:, total:, users:, findings: [Finding], counts: {信号 => 条数} }
  def call
    convos = conversations
    findings = convos.filter_map { |c| inspect_conversation(c) }
    { date: @date, total: convos.size, users: convos.map(&:user_id).uniq.size,
      findings: findings.sort_by { |f| -f.signals.size }, counts: tally(findings) }
  end

  private

  def conversations
    @account.crm_agent_conversations.where(created_at: @date.all_day).includes(:user).to_a
  end

  def inspect_conversation(convo)
    msgs = convo.messages.order(:id).to_a
    signals = detect(msgs)
    return nil if signals.empty?

    Finding.new(
      conversation_id: convo.id, user_name: convo.user&.name,
      question: first_question(msgs), signals: signals,
      tool_calls: msgs.count { |m| m.meta['tool'].present? },
      turns: msgs.count { |m| m.role == 'user' }
    )
  end

  # 信号名 => 判定。加新信号就在这里加一行。
  SIGNALS = {
    '原地打转：工具调用过多' => ->(_a, _msgs, tools) { tools.size >= FLAILING_TOOL_CALLS },
    '撞墙：工具连续查不到' => ->(a, msgs, _tools) { a.send(:dead_ends, msgs) >= 2 },
    '回头跟用户要信息' => ->(a, msgs, _tools) { a.send(:ask_back?, msgs) },
    '用户当场纠正' => ->(a, msgs, _tools) { a.send(:user_corrected?, msgs) },
    '拿占位值试工具' => ->(a, _msgs, tools) { a.send(:placeholder?, tools) },
    '有工具没跑完' => ->(_a, _msgs, tools) { tools.any? { |m| m.meta['status'].blank? } },
    '问一次就走' => lambda { |_a, msgs, tools|
      msgs.count { |m| m.role == 'user' } == 1 && tools.size >= 3
    }
  }.freeze

  def detect(msgs)
    tools = msgs.select { |m| m.meta['tool'].present? }
    hits = SIGNALS.filter_map { |name, check| name if check.call(self, msgs, tools) }
    (hits + [repeat_signal(tools)]).compact
  end

  def repeat_signal(tools)
    worst = tools.group_by { |m| m.meta['tool'] }.transform_values(&:size).max_by { |_, n| n }
    return nil if worst.nil? || worst.last < REPEAT_SAME_TOOL

    "换着词反复试：#{worst.first} 调了 #{worst.last} 次"
  end

  def dead_ends(msgs)
    msgs.count { |m| m.meta['tool'].present? && DEAD_END_HINTS.any? { |h| m.content.to_s.include?(h) } }
  end

  # 只看**最后一条**助手回答：中间问一句很正常，一轮结束还在要信息才是问题。
  def ask_back?(msgs)
    last = msgs.reverse.find { |m| m.role == 'assistant' && m.content.present? }
    last.present? && ASK_BACK_HINTS.any? { |h| last.content.include?(h) }
  end

  def user_corrected?(msgs)
    msgs.any? { |m| m.role == 'user' && USER_CORRECTION_HINTS.any? { |h| m.content.to_s.include?(h) } }
  end

  def placeholder?(tools)
    tools.any? { |m| PLACEHOLDER_ARGS.any? { |p| m.meta['args'].to_s.delete(' ').include?(p.delete(' ')) } }
  end

  def first_question(msgs)
    msgs.find { |m| m.role == 'user' }&.content.to_s.squish.truncate(80)
  end

  def tally(findings)
    findings.flat_map(&:signals).map { |s| s.split('：').first }.tally.sort_by { |_, n| -n }.to_h
  end
end
