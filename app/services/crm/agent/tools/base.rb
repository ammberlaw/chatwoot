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

  # 金额带千分位：外贸这边的数动辄七八位，「CNY 40949800.95」人得用手指着数。
  # zero: 控制 0 怎么显示——「未收 0」是有意义的真数，「金额 —」才是没填。
  def money(micros, currency = 'CNY', zero: '—')
    return zero if micros.blank?
    return zero if micros.to_i.zero? && zero != '0.00'

    amt = micros.to_i / 1e6
    "#{currency} #{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', amt))}"
  end

  def day(value) = value&.to_date&.to_s || '—'

  # 数量去掉没意义的小数尾巴：「500.000 个」读起来像个报错。
  def fnum(value)
    d = value.to_d
    d == d.to_i ? d.to_i.to_s : d.to_s('F')
  end
end
