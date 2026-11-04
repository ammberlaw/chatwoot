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

  # 「超时未接单」不按角色群发，单独定向到每张单当前该接的人（见 #notify_unacked）。
  # 按角色群发的毛病：商显的单该工程接，群发给 PMC 等于通知了一屋子不相干的人，
  # 真正该动的那位反而不在收件人里（2026-11-04 一张商显返单卡 16 天没人知道）。

  def perform
    Account.joins(:mes_production_orders).distinct.find_each do |account|
      alerts = Mes::AlertScannerService.new(account).call
      next if alerts.values.all?(&:blank?)

      notify_account(account, alerts)
      notify_unacked(account, alerts[:unacked])
    end
  end

  # 超时未接单：按「这张单该谁接」分组，各人只收到自己该接的那几张。
  # 同时抄送管理层——没人接单这件事本身就该让管理层看见。
  def notify_unacked(account, rows)
    return if rows.blank?

    by_user = Hash.new { |h, k| h[k] = [] }
    account.mes_production_orders.where(id: rows.filter_map { |r| r[:id] }).find_each do |po|
      po.ack_owner_ids.each { |uid| by_user[uid] << po }
    end
    admin_ids = account.account_users.select { |au| au.administrator? || au.crm_deputy_admin? }.map(&:user_id)
    (admin_ids - by_user.keys).each do |uid|
      by_user[uid] = account.mes_production_orders.where(id: rows.filter_map { |r| r[:id] }).to_a
    end

    by_user.each do |uid, orders|
      next if orders.blank?

      Mes::Notifier.notify(
        account: account, recipients: uid, kind: 'unacked_orders',
        title: "有 #{orders.size} 张生产订单超时没人接单",
        body: orders.first(8).map { |po|
          "#{po.order_no}｜#{Mes::ProductionOrder::STAGE_LABELS[po.stage]}｜等了 #{stall_days(po)} 天"
        }.join("\n")
      )
    rescue StandardError => e
      Rails.logger.warn("[MesDailyAlert] 未接单通知失败 user=#{uid}: #{e.message}")
    end
  end

  def stall_days(po)
    return 0 if po.stage_entered_at.blank?

    ((Time.current - po.stage_entered_at) / 1.day).floor
  end

  private

  def notify_account(account, alerts)
    account.account_users.includes(:user).find_each do |account_user|
      keys = keys_for(account_user)
      next if keys.blank?

      subset = keys.index_with { |k| jsonify(alerts[k]) }.select { |_, v| v.present? }
      next if subset.empty?

      notify_in_app(account, account_user, subset)
      MesAlertMailer.with(account: account, recipient: account_user.user.email, alerts: subset)
                    .daily_digest.deliver_later
    end
  end

  # 站内通知是主通道，邮件是捎带。
  #
  # 预警只走邮件时，收不到就是彻底收不到，而且没人知道：2026-09-28 起连续 5 期，
  # 熊莉莉/杨义/徐桥保/周方荣 四个人的企业邮箱一直退信（550 Mailbox not found），
  # 失败只躺在 sidekiq 的 dead 队列里。偏偏滞留预警发给 pmc+生产、逾期预警只发给 pmc，
  # 这四个人就是全部目标受众——于是那两类预警实际送达 0 人，只有管理员收到。
  #
  # 这些人天天在系统里，站内通知比邮箱地址对不对可靠得多。邮件照发（能收到的 6 个人照收）。
  KIND = 'alert_digest'.freeze
  LABELS = { overdue: '逾期', due_soon: '临近交期', stalled: '滞留', shortages: '缺料' }.freeze

  def notify_in_app(account, account_user, subset)
    parts = subset.map { |k, rows| "#{LABELS[k] || k} #{rows.size}" }
    Mes::Notifier.notify(
      account: account, recipients: account_user.user_id, kind: KIND,
      title: "生产预警周报：#{parts.join(' · ')}",
      body: digest_body(subset)
    )
  rescue StandardError => e
    # 站内通知发不出去不该把邮件也带崩——这是周报，少一条不如整批不发严重。
    Rails.logger.warn("[MesDailyAlert] 站内通知失败 user=#{account_user.user_id}: #{e.message}")
  end

  # 正文列具体对象，每类最多 5 个——点开通知就知道是哪几张单/哪几个料，不用再去翻列表。
  # 逾期/临近/滞留是订单（order_no），缺料是物料（material_name），两种行结构不一样。
  def digest_body(subset)
    subset.map do |k, rows|
      names = rows.first(5).filter_map { |r| row_label(r) }
      more = rows.size > 5 ? " 等 #{rows.size} 项" : ''
      "#{LABELS[k] || k}：#{names.join('、')}#{more}"
    end.join("\n")
  end

  def row_label(row)
    r = row.transform_keys(&:to_s)
    r['order_no'].presence || r['material_name'].presence
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

    # 多角色取并集：兼岗者收到各角色对应的预警类别。
    account_user.mes_roles.to_a.flat_map { |r| ROLE_KEYS[r] || [] }.uniq
  end
end
