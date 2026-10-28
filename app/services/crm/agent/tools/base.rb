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

  # 用完预算不等于任务黄了。必须让模型把「还差什么、下一句说什么就能接着做」讲清楚——
  # 2026-10-24 生产上那次群发 9 封只写成 7 封，用户得自己数才知道少了谁。
  BUDGET_MSG = '这一轮查询次数已经用完，别再调工具了。' \
               '用前面已经查到的信息直接回答用户，并且：' \
               '① 明确列出哪几项还没做完（点名，不要只说「还有一些」）；' \
               '② 告诉用户回一句什么就能接着做完剩下的。'.freeze

  # 每次工具调用都先扣预算。超了就回一句话让模型收口，而不是把这一轮废掉
  # （口径见 Crm::Agent::Scope#take_tool_budget!）。
  def call(args)
    return BUDGET_MSG unless scope.take_tool_budget!

    super
  end

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

  # 建完单自己验一遍（「发出前体检」那套，Crm::DocHealthCheck）。
  #
  # 原来建完只说一句「去核对一下」，等于把检查推回给人——而体检这件事
  # 系统本来就会做，还比人做得全（行金额、合计、币种、价格偏离、必填条款）。
  # 现在把结果接在建单回执后面，模型照着念出来，用户点进去之前就知道哪儿不对。
  #
  # 体检不通过**不回滚**：草稿本来就是让人改的，建出来再告诉他缺什么，
  # 比因为少填一个港口就整单失败、让他重说一遍要求强得多。
  def self_check(findings)
    return "自检通过：行金额、合计、币种、价格区间都对得上。\n" if findings.blank?

    warns = findings.select { |f| f.level == 'warn' }
    infos = findings - warns
    out = "自检发现 #{warns.size} 处要改"
    out << "、#{infos.size} 处可以先不管" if infos.any?
    out << "（**必须原样念给用户**，不要自己判断「问题不大」就略过）：\n"
    findings.each { |f| out << "· #{f.level == 'warn' ? '要改' : '提示'}｜#{f.title}#{detail_of(f)}\n" }
    out
  end

  def detail_of(finding)
    finding.detail.present? ? "：#{finding.detail}" : ''
  end

  # 数量去掉没意义的小数尾巴：「500.000 个」读起来像个报错。
  def fnum(value)
    d = value.to_d
    d == d.to_i ? d.to_i.to_s : d.to_s('F')
  end
end
