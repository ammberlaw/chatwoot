# 把 agent 这一轮「做了哪几步、每步在查什么、做完没有」记成一条条可渲染的步骤。
#
# 为什么要记完成状态：只记开始的话，屏幕上一排全是「正在查…」，看不出已经做完几步、
# 现在卡在哪一步——跟只写一句「执行中」没差多少。用户要的是看得见它一步步在干嘛。
#
# ⚠️ 这里**不报百分比**。每个工具就是一次数据库查询，要么在跑要么跑完，中间没有
# 可报的进度；编一个 0→100% 的数字等于造数据，而这套东西的全部价值就在于它说的是真的。
# 同理也没有「共 N 步」：模型是每一步才决定下一个工具调什么，开跑时根本不知道要几步。
class Crm::Agent::StepRecorder
  # 这一步在查**哪一个**东西。「查客户」和「查客户 · Alina.Petrova」差着一个量级——
  # 前者只说明它在忙，后者才让人判断得出它是不是在查对的东西。
  #
  # 只收人看得懂的参数，按「越具体越优先」排。**刻意不收 customer_id**：
  # 它是出现最多的参数（12 个工具都有），但摆出来是「· 2451」，还不如不摆；
  # 要换成客户名就得在这儿再查一次库，而这个类的本分是记录，不是查数据。
  # 一条都挑不出来就不摆副标题——少一行，好过摆个看不懂的东西。
  SUBJECT_KEYS = %w[doc_no order_no keyword name title task_title to_address subject website].freeze

  # 工具返回原文的留存长度。留它是为了让每日体检判断得出「这一步有没有撞墙」——
  # 工具查不到东西时那句话全在开头（「没找到单号 WT-123」「看不到 ID 12 这个客户」），
  # 200 字够了。
  #
  # 为什么不是存全文：一次 customer_emails 能返回几千字，一轮几十步攒起来把会话表撑大，
  # 而体检只认开头那句。也不是不存——以前一个字都不存，Crm::Agent::QualityAudit 的
  # 「撞墙」信号拿步骤标签（content 存的是「做客户背调」）去匹配查不到的话术，
  # 从上线起就没响过一次（2026-11-06 核实：生产 460 次调用，撞墙率恒为 0）。
  RESULT_DIGEST = 200

  # 这一轮崩了：工具跑到一半抛异常时 after_tool_result 不回调，那条步骤会永远停在
  # 「正在查…」。翻历史时一个转圈的图标看着像还在跑（生产 2026-11-03 背调崩在
  # steliau.fr 的那条就是），所以收尾时统一落成 failed，前端渲染成普通的一步。
  def self.close_dangling(conversation)
    conversation.messages.where(role: 'tool').where("meta->>'status' = 'running'").find_each do |step|
      step.update!(meta: step.meta.merge('status' => 'failed', 'ended_at' => Time.current.iso8601(3)))
    end
  end

  def initialize(conversation:, label:)
    @conversation = conversation
    @label = label # ->(call) { '查客户' }
  end

  def start(call, note: nil)
    text = note.present? ? "#{@label.call(call)}（#{note}）" : @label.call(call)
    @running = @conversation.messages.create!(
      role: 'tool', content: text,
      meta: { tool: call.name.to_s, args: call.arguments, status: 'running',
              subject: subject_of(call), started_at: Time.current.iso8601(3) }
    )
  end

  # 回调只给结果、不给是哪次调用，但 RubyLLM 是一个一个顺序执行的
  # （chat.rb#handle_tool_calls 里 each_value 串行），所以待收尾的永远是刚开的那条。
  def finish(result = nil)
    return if @running.nil?

    @running.update!(meta: @running.meta.merge(
      'status' => 'done', 'ended_at' => Time.current.iso8601(3), 'result_digest' => digest(result)
    ).compact)
    @running = nil
  end

  private

  # 工具返回的一律是给模型读的纯文本（见 Tools::Base 的类注释），原样截一段即可。
  # squish 掉换行：体检是按关键词匹配，多行排版只占长度不增信息。
  # 拿不到内容就不写这个键（finish 里 compact 掉），老消息因此和新消息一样是「没有」而不是空串。
  def digest(result)
    text = result.to_s.squish
    text.presence && text[0, RESULT_DIGEST]
  end

  def subject_of(call)
    args = call.arguments.to_h.transform_keys(&:to_s)
    key = SUBJECT_KEYS.find { |k| args[k].to_s.strip.present? }
    key && args[key].to_s.strip.truncate(40)
  end
end
