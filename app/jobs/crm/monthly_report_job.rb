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

      Crm::MonthlyReportMailer.with(
        account: account,
        recipient: account_user.user.email,
        recipient_name: account_user.user.name,
        report: report,
        month_label: label
      ).monthly_digest.deliver_later
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
