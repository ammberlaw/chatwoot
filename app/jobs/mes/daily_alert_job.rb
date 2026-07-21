# 每日扫描各账号 MES 预警，按角色把相关预警邮件给对应成员。
# 缺料→采购/仓管，逾期/临近/滞留→PMC，滞留→生产；管理员/副管理员收全部。
class Mes::DailyAlertJob < ApplicationJob
  queue_as :scheduled_jobs

  ROLE_KEYS = {
    'pmc' => %i[overdue due_soon stalled],
    'buyer' => %i[shortages],
    'warehouse' => %i[shortages],
    'production' => %i[stalled]
  }.freeze
  ALL_KEYS = %i[overdue due_soon stalled shortages].freeze

  def perform
    Account.joins(:mes_production_orders).distinct.find_each do |account|
      alerts = Mes::AlertScannerService.new(account).call
      next if alerts.values.all?(&:blank?)

      notify_account(account, alerts)
    end
  end

  private

  def notify_account(account, alerts)
    account.account_users.includes(:user).find_each do |account_user|
      keys = keys_for(account_user)
      next if keys.blank?

      subset = keys.index_with { |k| jsonify(alerts[k]) }.select { |_, v| v.present? }
      next if subset.empty?

      MesAlertMailer.with(account: account, recipient: account_user.user.email, alerts: subset)
                    .daily_digest.deliver_later
    end
  end

  # sidekiq 参数须原生 JSON 类型：BigDecimal→Float、Time→字符串。
  def jsonify(rows)
    Array(rows).map do |row|
      row.transform_values do |v|
        case v
        when BigDecimal then v.to_f
        when Time, ActiveSupport::TimeWithZone then v.iso8601
        else v
        end
      end
    end
  end

  def keys_for(account_user)
    return ALL_KEYS if account_user.administrator? || account_user.crm_deputy_admin?

    ROLE_KEYS[account_user.mes_role]
  end
end
