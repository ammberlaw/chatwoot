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
  def finish
    return if @running.nil?

    @running.update!(meta: @running.meta.merge('status' => 'done', 'ended_at' => Time.current.iso8601(3)))
    @running = nil
  end

  private

  def subject_of(call)
    args = call.arguments.to_h.transform_keys(&:to_s)
    key = SUBJECT_KEYS.find { |k| args[k].to_s.strip.present? }
    key && args[key].to_s.strip.truncate(40)
  end
end
