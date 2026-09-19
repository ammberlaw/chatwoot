# 每日催收预警：把临期/逾期的应收分期推给**订单归属业务员**（催款的人）与财务，
# 应付到期只推财务（付款是财务的事，业务员看不到应付）。
#
# ⚠️ 防重复轰炸：同一笔分期只在**状态变化时**提醒一次（临期→逾期算变化），
# 不是每天把同一条再喊一遍。判据＝该收件人有没有一条未读的同标题通知；
# 标题里带了单号与状态，状态一变标题就变，自然会再提醒一次。
# 通知被点掉（已读）也不会重复喊——那是人已经看到了。
class Erp::DailyAlertJob < ApplicationJob
  queue_as :scheduled_jobs

  INSTALLMENT_KIND = 'erp_installment_due'.freeze
  PAYABLE_KIND = 'erp_payable_due'.freeze

  def perform
    Account.joins(:erp_receivables).distinct.find_each do |account|
      alerts = Erp::AlertScannerService.new(account).call
      next if alerts.values.all?(&:blank?)

      finance_ids = finance_user_ids(account)
      notify_receivables(account, alerts, finance_ids)
      notify_payables(account, alerts[:payable_due], finance_ids)
    end
  end

  private

  # 财务与管理员：能进 ERP 且有应收/付款能力的人。
  def finance_user_ids(account)
    account.account_users.select { |au| au.can_access_erp? && au.erp_can?(:receivable) }.map(&:user_id)
  end

  def notify_receivables(account, alerts, finance_ids)
    (alerts[:overdue] + alerts[:due_soon]).each do |row|
      title = receivable_title(row)
      # 业务员是催款人，财务是收款人，两边都要知道。
      recipients = ([row[:owner_id]] + finance_ids).compact.uniq
      notify_once(account, recipients, INSTALLMENT_KIND, title, receivable_body(row))
    end
  end

  def notify_payables(account, rows, finance_ids)
    Array(rows).each do |row|
      notify_once(account, finance_ids, PAYABLE_KIND, payable_title(row), payable_body(row))
    end
  end

  # 逐人判重：该收件人已有同标题未读通知就跳过（状态没变，不用再喊）。
  def notify_once(account, recipients, kind, title, body)
    Array(recipients).uniq.each do |user_id|
      next if account.mes_notifications.exists?(recipient_id: user_id, kind: kind, title: title, read_at: nil)

      Mes::Notifier.notify(account: account, recipients: user_id, kind: kind, title: title, body: body)
    end
  end

  def receivable_title(row)
    state = row[:days].positive? ? "逾期 #{row[:days]} 天" : "#{-row[:days]} 天后到期"
    "#{row[:kind_label]}#{state}：#{row[:receivable_no]}"
  end

  def receivable_body(row)
    amount = format('%.2f', row[:open_micros].to_i / 1_000_000.0)
    [
      "#{row[:customer_name]}（#{row[:order_no]}）",
      "未收 #{row[:currency]} #{amount}",
      "到期日 #{row[:due_date]}"
    ].compact.join(' · ')
  end

  def payable_title(row)
    state = row[:days].positive? ? "已逾期 #{row[:days]} 天" : "#{-row[:days]} 天后到期"
    "应付#{state}：#{row[:payable_no]}"
  end

  def payable_body(row)
    amount = format('%.2f', row[:open_micros].to_i / 1_000_000.0)
    "#{row[:supplier_name]} · 未付 #{row[:currency]} #{amount} · 约定付款日 #{row[:due_date]}"
  end
end
