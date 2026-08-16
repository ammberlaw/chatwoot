# 每月 1 号在「团队沟通」提醒成员填报上月绩效考核表与提成表（对齐工作月报的调度形态）。
# 发送人取账号管理员（系统提醒身份）；仅提醒会自填表的角色（业务员 / 主管）。
# 单条失败由 Chat::NotifyService 内部兜住，不中断整体。
class Crm::MonthlyFilingReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  # month_str 供手动补发 / 测试（如 '2026-07'）；默认取上一个自然月。
  def perform(month_str = nil)
    month = month_str ? Date.parse("#{month_str}-01") : Date.current.prev_month.beginning_of_month
    Account.where(id: Crm::Customer.distinct.select(:account_id)).find_each do |account|
      remind_for_account(account, month)
    end
  end

  private

  def remind_for_account(account, month)
    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)
    label = "#{month.year}年#{month.month}月"
    content = "【月度提醒】新的一月开始了，请及时到「考核表」填报 #{label} 绩效考核表，并在「提成表」填报当月提成。"
    account.account_users.includes(:user).find_each do |account_user|
      next unless fills_sheets?(account_user)

      notifier.notify(account_user.user_id, content)
    end
  end

  # 只提醒会自填表的角色：业务员 / 主管（管理员 / 人事等跳过）。
  def fills_sheets?(account_user)
    %w[sales manager].include?(account_user.crm_role)
  end
end
