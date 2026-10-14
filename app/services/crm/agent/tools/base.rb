# agent 工具的基类。
#
# 每个工具都拿着一个 Crm::Agent::Scope——取数一律经它，看到的和这个人自己点进去看到的一样。
# 工具绝不直接用 Account.xxx 全表查，那等于借 AI 越权。
#
# 返回值一律是「给模型读的纯文本」：结构化 JSON 对小模型反而不友好，
# 而且这些内容会原样摆进对话里给用户看，文本更好读。
class Crm::Agent::Tools::Base < RubyLLM::Tool
  # RubyLLM 默认拿类名推工具名，带上命名空间会变成 crm-agent-tools-xxx 这种长串。
  # 这里统一取最后一段的下划线写法（find_customer / customer_emails …）。
  def name = self.class.name.demodulize.underscore

  def initialize(scope)
    @scope = scope
    super()
  end

  attr_reader :scope

  private

  # 文本一律截断：一封几万字的邮件能把上下文撑爆，后面的工具结果就被挤掉了。
  def clip(text, max)
    t = text.to_s.strip
    t.length > max ? "#{t[0, max]}…（已截断）" : t
  end

  def money(micros, currency = 'CNY')
    return '—' if micros.blank? || micros.to_i.zero?

    format('%<cur>s %<amt>.2f', cur: currency, amt: micros.to_i / 1e6)
  end

  def day(value) = value&.to_date&.to_s || '—'
end
