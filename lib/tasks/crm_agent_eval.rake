# AI 助手回归评测：rake crm:agent:eval
#
# 为什么是 rake 不是 spec：每条用例都要真打一次模型（几秒 + 花钱），
# 不该混进 CI 的 spec 套件里每次都跑。改提示词/加工具之后手动跑一遍就够。
#
# 判定靠两样东西：
#   · 调了哪些工具 —— agent 自己会把每次调用记成 role='tool' 的消息（StepRecorder）
#   · 最终回答文本 —— 必须/不该出现的字样
# 两样都不靠人看顺不顺眼。
namespace :crm do
  namespace :agent do
    CASES_PATH = Rails.root.join('lib/crm_agent_eval/cases.yml')

    desc 'AI 助手回归评测（只在开发环境跑：会真打模型、会建临时对话）'
    task eval: :environment do
      abort '❌ 这个任务只在开发环境跑（会真打模型并写入对话）' if Rails.env.production?

      account = Account.first or abort '❌ 没有账号'
      cases = YAML.safe_load_file(CASES_PATH)
      ctx = EvalContext.new(account)
      # 失败的再跑一次：模型本身有抖动，同一道题两次可能走不同的工具路线
      # （2026-10-27 实测：reply_by_email_id 一次走 draft_reply、一次走 my_worklist）。
      # 一次红就判死会让这份尺子自己变得不可信；但也不能默默重试到绿——
      # 重试才过的标成「抖」，它和稳定通过是两回事，值得单独盯。
      results = cases.map do |c|
        first = run_case(account, ctx, c)
        next first if first[:ok]

        second = run_case(account, ctx, c)
        second[:ok] ? second.merge(flaky: true, why: "重跑才过（首次：#{first[:why]}）") : second
      end

      puts
      puts format('%-34s %-6s %s', '用例', '结果', '说明')
      puts '-' * 92
      results.each do |r|
        mark = if r[:ok] && r[:flaky] then '⚠️ 抖'
               elsif r[:ok] then '✅'
               else '❌'
               end
        puts format('%-34s %-6s %s', r[:id], mark, r[:why])
      end
      failed = results.count { |r| !r[:ok] }
      flaky = results.count { |r| r[:flaky] }
      puts '-' * 92
      puts "#{results.size} 条，失败 #{failed} 条，抖动 #{flaky} 条"
      exit(1) if failed.positive?
    end

    # 把用例里的占位符换成这个库里真实存在的数据——写死 ID 的评测集活不过一次 reseed。
    class EvalContext
      def initialize(account) = @account = account

      def inbox_email
        @inbox_email ||= @account.crm_emails.where(folder: 'INBOX')
                                 .where.not(crm_customer_id: nil).where.not(owner_id: nil)
                                 .order(email_date: :desc).first
      end

      def customer_name
        @customer_name ||= @account.crm_customers.where.not(name: [nil, '']).first&.name
      end

      def open_order_no
        @open_order_no ||= @account.mes_production_orders.where.not(order_no: nil).order(id: :desc).first&.order_no
      end

      # 建单类用例必须用「这个人自己看得见」的客户。写死第一个客户的话，业务员身份下
      # find_customer 根本查不到，用例会以「没调到 draft_quote」的形式假红——
      # 看着像提示词坏了，其实是尺子自己拿错了数据。
      def my_customer_name(actor)
        return customer_name if actor.nil?

        Crm::Agent::Scope.new(account: @account, account_user: actor)
                         .customers.where.not(name: [nil, '']).first&.name || customer_name
      end

      # 知识库里抽出过正文的那篇文档的名字。建单类用例一样的道理——写死型号
      # 换一次种子数据就失效，这里现查一篇真有正文的。
      def extracted_doc_name
        @extracted_doc_name ||= @account.crm_knowledge_docs.kept
                                        .where(extract_state: 'done').order(:id).first&.name
      end

      def fill(text, actor = nil)
        text.to_s
            .gsub('{{inbox_email_id}}', inbox_email&.id.to_s)
            .gsub('{{customer_name}}', customer_name.to_s)
            .gsub('{{my_customer_name}}', my_customer_name(actor).to_s)
            .gsub('{{extracted_doc_name}}', extracted_doc_name.to_s)
            .gsub('{{open_order_no}}', open_order_no.to_s)
      end
    end

    # 身份：用例说 sales/warehouse/... 就在库里找一个真这样的人，找不到就回落到第一个。
    def self.actor_for(account, kind, ctx)
      users = account.account_users.includes(:user).to_a
      found =
        case kind
        when 'sales' then users.find { |a| a.crm_role == 'sales' && a.effective_mes_roles.empty? }
        when 'admin' then users.find(&:administrator?)
        when 'owner_of_inbox_email' then users.find { |a| a.user_id == ctx.inbox_email&.owner_id }
        else users.find { |a| a.effective_mes_roles.include?(kind) }
        end
      found || users.first
    end

    def self.run_case(account, ctx, kase)
      actor = actor_for(account, kase['as'], ctx)
      ask = ctx.fill(kase['ask'], actor)
      # 评测会真的建草稿、开问题单、写记忆——跑完必须擦干净，
      # 否则跑几轮下来开发库里全是 eval 留下的垃圾（今天就这么污染过）。
      mark = { emails: account.crm_emails.maximum(:id).to_i,
               issues: (Crm::IssueReport.maximum(:id).to_i if defined?(Crm::IssueReport)).to_i,
               memories: Crm::AgentMemory.maximum(:id).to_i,
               # 建单类用例会真的落一张报价单/PI（带明细行）。原来水位里没有这两样，
               # 跑一轮就在库里留一张草稿，跑十轮留十张——单据列表会被评测垃圾灌满。
               quotes: account.crm_quotes.maximum(:id).to_i,
               pis: account.crm_pis.maximum(:id).to_i }
      # 用例可以预置一条记忆（测跨对话记忆有没有生效）
      seed = kase['memory'].presence &&
             Crm::AgentMemory.remember!(account: account, user_id: actor.user_id, content: kase['memory'])

      conv = Crm::AgentConversation.create!(account: account, user: actor.user, title: "eval:#{kase['id']}")
      # 用例可以模拟「用户正开着哪一页」（测上下文注入）
      Crm::Agent::Runner.new(conversation: conv, page_context: kase['page_context']).perform(ask)

      answer = conv.messages.where(role: 'assistant').order(:id).last&.content.to_s
      tools  = conv.messages.where(role: 'tool').map { |m| m.meta['tool'].to_s }.uniq

      { id: kase['id'], **judge(kase, answer, tools) }
    rescue StandardError => e
      { id: kase['id'], ok: false, why: "跑挂了：#{e.class} #{e.message.to_s.truncate(60)}" }
    ensure
      conv&.destroy
      seed&.destroy
      cleanup(account, mark) if mark
    end

    # 擦掉这条用例跑出来的副产物（只删 id 大于开跑时水位的，不碰既有数据）。
    def self.cleanup(account, mark)
      account.crm_emails.where('id > ?', mark[:emails]).destroy_all
      # destroy_all 不是 delete_all：明细行靠 dependent: :destroy 跟着走，
      # delete_all 会把 crm_quote_line_items / crm_pi_items 留成孤儿。
      account.crm_quotes.where('id > ?', mark[:quotes]).destroy_all
      account.crm_pis.where('id > ?', mark[:pis]).destroy_all
      Crm::AgentMemory.where('id > ?', mark[:memories]).delete_all
      Crm::IssueReport.where('id > ?', mark[:issues]).delete_all if defined?(Crm::IssueReport)
    rescue StandardError => e
      warn "清理失败（不影响评测结果）：#{e.class} #{e.message}"
    end

    def self.judge(kase, answer, tools)
      want = Array(kase['expect_tools'])
      if want.any? && (want & tools).empty?
        return { ok: false, why: "没调到 #{want.join('/')}（实际：#{tools.presence&.join(',') || '没调工具'}）" }
      end

      banned = Array(kase['forbid_tools']) & tools
      return { ok: false, why: "不该调 #{banned.join(',')}" } if banned.any?

      inc = Array(kase['must_include'])
      return { ok: false, why: "回答里没出现 #{inc.join('/')}" } if inc.any? && inc.none? { |w| answer.include?(w) }

      hit = Array(kase['must_not_include']).select { |w| answer.include?(w) }
      return { ok: false, why: "回答里出现了不该有的 #{hit.join(',')}" } if hit.any?

      if kase['no_question'] && answer.match?(/[?？]\s*\z/)
        return { ok: false, why: '该动手却以反问收尾' }
      end

      { ok: true, why: tools.presence&.join(',') || '（未调工具）' }
    end
  end
end
