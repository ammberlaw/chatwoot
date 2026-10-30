# AI 助手每日体检：昨天它在哪儿掉链子，推一条给管理员。
#
# 两段式，刻意分开：
#   ① Crm::Agent::QualityAudit     —— 纯机检（计数 + 字符串），同样的对话算几遍都一样，可以逐日比
#   ② Crm::Agent::QualityDiagnosis —— 一天只调一次模型，把异常对话读一遍，分成
#      提示词 / 缺工具 / 数据 / 系统 四类
#
# **只出诊断，不自动改任何东西。** 提示词是全公司几十号人的行为规范，改错了不报错、
# 只会悄悄变笨；而且 2026-10-30 那两次真正的修复（按邮件ID读信、按发件人搜邮件）
# 都是「缺工具」，自动改提示词永远碰不到。
#
# 照 DailyBriefJob 的规矩：没问题就不发——每天一条「一切正常」，三天后就没人看了。
class Crm::AgentQualityJob < ApplicationJob
  queue_as :scheduled_jobs

  PREFIX = '【AI 助手体检】'.freeze
  MAX_LISTED = 5

  # date 供手工补跑：Crm::AgentQualityJob.perform_now(Date.new(2026,10,29))
  def perform(date = Date.yesterday)
    Account.where(id: Crm::AgentConversation.distinct.select(:account_id)).find_each do |account|
      report_for(account, date)
    end
  end

  private

  def report_for(account, date)
    audit = Crm::Agent::QualityAudit.new(account: account, date: date).call
    return if audit[:findings].blank?

    text = compose(account, audit)
    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)
    recipients(account).each do |account_user|
      next if sent_today?(account, sender.id, account_user.user_id)

      notifier.notify(account_user.user_id, text)
    end
  end

  # 只推给管理员和副管理员：这是产品质量报告，不是业务提醒，业务员收到只会当噪音。
  def recipients(account)
    account.account_users.where(crm_role: 'deputy_admin')
           .or(account.account_users.where(role: :administrator))
  end

  def sent_today?(account, sender_id, user_id)
    conversation_ids = account.chat_conversations.where(kind: 'direct')
                              .joins(:participants)
                              .where(chat_participants: { user_id: user_id }).select(:id)
    Chat::Message.where(conversation_id: conversation_ids, sender_id: sender_id)
                 .where('content LIKE ?', "#{PREFIX}%")
                 .exists?(created_at: Time.zone.today.all_day)
  end

  def compose(account, audit)
    diagnosis = Crm::Agent::QualityDiagnosis.new(account: account, audit: audit).call
    [headline(audit), diagnosis_block(diagnosis), evidence_block(audit)].compact_blank.join("\n\n")
  end

  def headline(audit)
    "#{PREFIX}#{audit[:date].strftime('%-m月%-d日')}\n" \
      "昨天 #{audit[:users]} 人用了 #{audit[:total]} 轮，其中 #{audit[:findings].size} 轮有问题。" \
      "#{audit[:counts].map { |k, v| "#{k} #{v}" }.join('｜')}"
  end

  # 模型挂了就只发机检部分——体检不能因为诊断失败就整条不发。
  def diagnosis_block(diagnosis)
    return nil if diagnosis.blank?

    issues = Array(diagnosis['issues']).first(3).map.with_index(1) do |issue, i|
      "#{i}. 【#{issue['kind']}】#{issue['title']}\n   依据：#{issue['evidence']}\n   建议：#{issue['fix']}"
    end
    return diagnosis['overall'] if issues.empty?

    "#{diagnosis['overall']}\n\n#{issues.join("\n")}"
  end

  def evidence_block(audit)
    rows = audit[:findings].first(MAX_LISTED).map do |f|
      "· #{f.user_name}｜#{f.question.presence || '（图片/附件）'}\n  工具 #{f.tool_calls} 次、#{f.turns} 轮｜#{f.signals.join('、')}"
    end
    more = audit[:findings].size - rows.size
    ['机检命中的对话：', *rows, (more.positive? ? "（另有 #{more} 轮，去「AI 助手」历史里翻）" : nil)].compact.join("\n")
  end
end
