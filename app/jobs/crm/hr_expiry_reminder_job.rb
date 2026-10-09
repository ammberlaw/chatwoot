# 人事到期提醒：试用期到期前 7 天、劳动合同到期前 1 个月，在「团队沟通」通知人事账号。
#
# 每天跑，但同一个人、同一个到期日只提醒一次——判据是人事那条单聊里有没有发过同一条
# （标题 + 工号 + 到期日三者都对上）。所以：
#   · 某天服务没跑到，第二天补得上，不会漏；
#   · 已经到期还没办（状态仍是试用）的，首次提醒后保持安静，不天天轰炸；
#   · 续签改了合同到期日，日期变了会重新提醒一次。
class Crm::HrExpiryReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  PROBATION_AHEAD_DAYS = 7
  PROBATION_LABEL = '试用期到期提醒'.freeze
  CONTRACT_LABEL = '劳动合同到期提醒'.freeze

  def perform
    Account.where(id: Crm::Employee.distinct.select(:account_id)).find_each do |account|
      remind_for_account(account)
    end
  end

  private

  def remind_for_account(account)
    hr_ids = account.account_users.where(crm_role: 'hr').pluck(:user_id)
    return if hr_ids.empty?

    rows = probation_rows(account) + contract_rows(account)
    return if rows.empty?

    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)
    conversations = Chat::CreateConversationService.new(account: account, creator: sender)
    hr_ids.each do |hr_id|
      conversation = conversations.find_or_create_direct(hr_id)
      rows.each { |row| notifier.notify(hr_id, row[:content]) unless sent_before?(conversation, row) }
    end
  end

  # 试用期到期：状态仍是「试用」且未离职，到期日在 7 天内（含已到期还没转正的）。
  # 到期日走 Crm::Employee#probation_end_date（转正日期优先，否则入职日 + 试用期月数）——
  # 生产上多数人只填了试用期月数没填转正日期，只认 regular_date 会一个都查不出来。
  def probation_rows(account)
    deadline = Date.current + PROBATION_AHEAD_DAYS
    rows = account.crm_employees.where(status: 'PROBATION', resign_date: nil).includes(:department).filter_map do |employee|
      date = employee.probation_end_date
      next if date.blank? || date > deadline

      row(employee, PROBATION_LABEL, date, "试用期 #{date} 到期（#{due_label(date)}），请及时办理转正")
    end
    rows.sort_by { |r| r[:date] }
  end

  def contract_rows(account)
    scope = account.crm_employees.where.not(status: 'RESIGNED').where(resign_date: nil)
                   .where(contract_end_date: ..(Date.current + 1.month))
    scope.includes(:department).order(:contract_end_date).map do |employee|
      date = employee.contract_end_date
      row(employee, CONTRACT_LABEL, date, "劳动合同 #{date} 到期（#{due_label(date)}），请及时安排续签")
    end
  end

  def row(employee, label, date, detail)
    who = [employee.employee_no, employee.department&.name].compact_blank.join(' · ')
    { label: label, no: employee.employee_no, date: date, content: "【#{label}】#{employee.name}（#{who}）#{detail}。" }
  end

  def due_label(date)
    days = (date - Date.current).to_i
    return '就是今天' if days.zero?

    days.positive? ? "还有 #{days} 天" : "已超期 #{-days} 天"
  end

  def sent_before?(conversation, row)
    like = "【#{row[:label]}】%#{Chat::Message.sanitize_sql_like(row[:no].to_s)}%#{row[:date]}%"
    conversation.messages.exists?(['content LIKE ?', like])
  end
end
