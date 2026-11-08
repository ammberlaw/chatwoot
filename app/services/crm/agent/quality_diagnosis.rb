# 把机检出的异常对话交给模型读一遍，写成人话的诊断。
#
# 机检（Crm::Agent::QualityAudit）只知道「这一轮调了 21 次工具、最后还在要信息」，
# 不知道**为什么**。而「为什么」恰恰决定了该改什么：
#   · 提示词问题 —— 它有工具、也查得到，就是没按该有的顺序办
#   · 缺工具     —— 用户给的线索足够，但没有能接住的入口（2026-10-30 两次真修复都是这类）
#   · 数据问题   —— 工具没毛病，是库里的数据不全（例如 44.6% 的邮件没挂到客户名下）
#   · 系统 bug   —— 跟助手无关，是别的功能坏了
#
# 分类这件事模型做得比规则好，但**只出诊断、不改任何东西**——
# 提示词是 42 个人的行为规范，改错了不会报错，只会悄悄变笨。
class Crm::Agent::QualityDiagnosis
  # 一天只读这么多轮对话。按命中信号数排序取最严重的几轮，省钱也省上下文。
  MAX_CONVERSATIONS = 5
  MAX_BODY = 600
  # 工具返回摘要在诊断稿里的长度。存的本来就只有 200 字，这里再收一道：
  # 一轮能有二十几次调用，全摆上去工具结果会把对话正文挤出上下文。
  MAX_TOOL_RESULT = 150

  SYSTEM = <<~PROMPT.freeze
    你在给一个企业 CRM 里的 AI 助手做每日质检。下面是昨天表现异常的几轮真实对话。
    你的任务是judge出**该改什么**，不是复述现象。用简体中文。

    每一条问题必须归到四类之一，这个分类决定了谁去改：
    · 【提示词】它手上有工具、数据也查得到，只是没按该有的顺序或口径办事。
    · 【缺工具】用户给的线索足够办这件事，但没有一个工具能接住。
    · 【数据】工具和提示词都没毛病，是库里的数据不全或没关联。
    · 【系统】跟助手无关，是别的功能坏了（单据卡住、权限判错等）。

    规矩：
    - 最多列 3 条，按「改了之后能救多少轮对话」排序，不要凑数。
    - 每条必须引用具体会话号和现象，不许泛泛而谈「应该更智能」。
    - 分不清属于哪类就归【待查】，并写明还需要看什么才能判断。
    - 不要建议「增加提示词让它更努力」这种没有可执行动作的话。

    只返回一个 JSON 对象，不要代码块包裹：
    {
      "overall": "一句话概括昨天整体表现",
      "issues": [
        { "kind": "提示词|缺工具|数据|系统|待查",
          "title": "一句话说清是什么问题",
          "evidence": "会话号 + 具体现象",
          "fix": "具体该做什么改动" }
      ]
    }
  PROMPT

  def initialize(account:, audit:)
    @account = account
    @audit = audit
  end

  # 返回 { 'overall' => ..., 'issues' => [...] }；模型不可用时返回 nil（机检报告照发）。
  def call
    return nil if @audit[:findings].blank?

    parsed = Crm::EmailAiService.new(account: @account).ask_json(SYSTEM, transcript)
    parsed.is_a?(Hash) ? parsed : nil
  rescue StandardError => e
    Rails.logger.error("[AgentQuality] 诊断失败 #{e.class}: #{e.message}")
    nil
  end

  private

  def transcript
    head = "昨天共 #{@audit[:total]} 轮对话、#{@audit[:users]} 人在用，" \
           "机检命中 #{@audit[:findings].size} 轮。信号分布：#{@audit[:counts].inspect}"
    [head, *@audit[:findings].first(MAX_CONVERSATIONS).map { |f| conversation_text(f) }].join("\n\n")
  end

  def conversation_text(finding)
    convo = @account.crm_agent_conversations.find_by(id: finding.conversation_id)
    msgs = convo ? convo.messages.order(:id) : []
    ["── 会话 #{finding.conversation_id}（#{finding.user_name}）机检信号：#{finding.signals.join('、')}",
     *msgs.filter_map { |m| line(m) }].join("\n")
  end

  # 工具那行要带上它查到了什么（result_digest，见 StepRecorder）。
  # 以前只给工具名和参数，却要模型判断「为什么掉链子」——查到了没查到都长一个样，
  # 它只能猜。有了返回摘要，「撞墙」和「查到了却没用上」才分得开。
  # 2026-11-06 之前的老会话没有这个字段，那几行照旧只有工具名。
  def line(msg)
    if msg.meta['tool'].present?
      head = "  [工具] #{msg.meta['tool']} #{msg.meta['args'].to_s.truncate(120)}"
      digest = msg.meta['result_digest'].to_s
      digest.present? ? "#{head}\n         → #{digest.truncate(MAX_TOOL_RESULT)}" : head
    elsif msg.content.present?
      "  #{msg.role == 'user' ? '用户' : '助手'}：#{msg.content.to_s.squish.truncate(MAX_BODY)}"
    end
  end
end
