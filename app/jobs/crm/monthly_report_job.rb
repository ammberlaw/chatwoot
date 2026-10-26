# 工作月报：每月 1 号发上月经营数据给各业务员/主管/管理员（各按查看权限范围）。
# 对齐 Mes::DailyAlertJob 的形态（遍历账号→成员→按角色发信）。
# 收件人限销售相关角色（业务员/主管/CRM管理员/超管），跳过 HR 等无关角色；
# 无目标且无成交无新客的成员跳过，避免发空报。
class Crm::MonthlyReportJob < ApplicationJob
  queue_as :scheduled_jobs

  # month_str 供手动补发/测试（如 '2026-07'）；默认取上一个自然月。
  def perform(month_str = nil)
    report_month = month_str ? Date.parse("#{month_str}-01") : Date.current.prev_month.beginning_of_month
    Account.where(id: Crm::Customer.distinct.select(:account_id)).find_each do |account|
      next unless Crm::PublicPoolSetting.for_account(account).monthly_report_enabled?

      send_for_account(account, report_month)
    end
  end

  private

  def send_for_account(account, report_month)
    label = "#{report_month.year} 年 #{report_month.month} 月"
    account.account_users.includes(:user).find_each do |account_user|
      next unless recipient?(account_user)

      report = Crm::MonthlyReportService.new(account, account_user, report_month).call
      next if skip_empty?(report)

      notify_in_app(account, account_user, report, label)
      Crm::MonthlyReportMailer.with(
        account: account,
        recipient: account_user.user.email,
        recipient_name: account_user.user.name,
        report: jsonify(report),
        month_label: label
      ).monthly_digest.deliver_later
    end
  end

  # 站内通知是主通道，邮件是捎带。
  #
  # users.email 是**登录账号**，不保证是能收信的邮箱——41 个成员里只有 12 个在 CRM 里
  # 绑了真实邮箱，而且绑的那个常常和登录账号不是同一个地址。已证实至少 4 个登录账号
  # 投不进去（550 Mailbox not found，见 Mes::DailyAlertJob 的说明）。
  # 月报是本系统最后一个只走邮件的定时任务，其余六个早就都走站内通知了。
  #
  # 金额在正文里按元摆出来，点开就看得到，不用等邮件。
  def notify_in_app(account, account_user, report, label)
    sender = Crm::SystemUser.for(account)
    conversation = Chat::CreateConversationService.new(account: account, creator: sender)
                                                  .find_or_create_direct(account_user.user_id)
    text = digest_text(report, label)
    # 同一个月只发一次：手动补发（perform('2026-09')）不该把上次那条再刷一遍。
    return if conversation.messages.exists?(['content LIKE ?', "#{Chat::Message.sanitize_sql_like(text.lines.first.to_s.strip)}%"])

    Chat::NotifyService.new(account: account, sender: sender).notify(account_user.user_id, text)
  rescue StandardError => e
    Rails.logger.warn("[MonthlyReport] 站内通知失败 user=#{account_user.user_id}: #{e.message}")
  end

  def digest_text(report, label)
    [
      "【#{label} 工作月报】#{report[:scope_label]}",
      "成交额 #{yuan(report[:amount_micros])}#{pct(report[:amount_mom_pct])}",
      "新增客户 #{report[:new_customers].to_i}#{pct(report[:customers_mom_pct])}",
      target_line(report),
      champion_line(report)
    ].compact.join("\n")
  end

  def target_line(report)
    return nil unless report[:year_target_micros].to_i.positive?

    "年度目标 #{yuan(report[:year_target_micros])}，累计完成 #{yuan(report[:ytd_amount_micros])}"
  end

  def champion_line(report)
    return nil if report[:champion_name].blank?

    "本月冠军 #{report[:champion_name]} #{yuan(report[:champion_amount_micros])}"
  end

  def yuan(micros)
    "¥#{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', micros.to_i / 1e6))}"
  end

  def pct(value)
    return '' if value.nil?

    "（环比 #{value.to_f.positive? ? '+' : ''}#{value}%）"
  end

  # sidekiq 参数必须是原生 JSON 类型。几个金额字段是 SQL SUM 出来的 BigDecimal，
  # 直接丢给 deliver_later 会抛 ArgumentError——而异常发生在本 job 里，整个循环当场中断，
  # **后面的人一封都收不到**（2026-10-01 全公司月报就是这么没发出去的）。
  # 同样的坑 Mes::DailyAlertJob 早就踩过并修了，这里照抄它的做法。
  #
  # micros 本来就是整数，取 to_i 不丢精度；百分比那几个是 round(2) 的 Float，原样传。
  def jsonify(report)
    report.transform_values do |v|
      case v
      when BigDecimal then v.frac.zero? ? v.to_i : v.to_f
      when Time, ActiveSupport::TimeWithZone then v.iso8601
      else v
      end
    end
  end

  # 只发销售业绩相关角色：超管 / CRM管理员 / 主管 / 业务员（HR 等跳过）。
  def recipient?(account_user)
    account_user.administrator? ||
      %w[deputy_admin manager sales].include?(account_user.crm_role)
  end

  # 上月毫无经营活动且未设年度目标的成员不发（多为非一线或新号）。
  def skip_empty?(report)
    report[:amount_micros].to_i.zero? &&
      report[:new_customers].to_i.zero? &&
      report[:year_target_micros].to_i.zero?
  end
end
