# 孤儿审计：系统里数据齐全、却没有任何人会看到的东西。
#
# 这类问题不报错、不进任何人的待办，就静静烂着，只能靠人偶然发现：
#   · 2026-11-04 查出 5 张老款返单卡了 12~16 天，从没进过任何人的待办
#   · 同日查出某同事离职三个月，名下邮箱还在后台每分钟认证失败
#   · 2026-11-05 查出当天办离职的同事名下 5 张在产订单无人接手（已走到领料/入库）
#
# 只读不改——清理要人来判断。两个入口共用这份逻辑：
#   rake wintouch:orphans   随时手查
#   Crm::OrphanAuditJob     每月 1 号推给管理层
class Crm::OrphanAuditService
  # 接单超时多久才算「烂着」。4 工作小时是接单时限，这里要拖过一整个工作日
  # 才报——刚进阶段还没来得及接属于正常节奏，天天报会让人麻木。
  STALE_ACK_HOURS = 8

  def initialize(account)
    @account = account
  end

  # [{ title:, why:, rows: [字符串] }]，rows 为空的已剔除。
  def call
    [stale_unacked, departed_owners, ownerless_mail, dead_board_owners, never_used_accounts]
      .reject { |s| s[:rows].empty? }
  end

  def total(sections = call) = sections.sum { |s| s[:rows].size }

  private

  attr_reader :account

  def stale_unacked
    rows = Mes::AlertScannerService.new(account).call[:unacked].to_a
                                   .select { |r| r[:hours].to_i >= STALE_ACK_HOURS }
                                   .sort_by { |r| -r[:hours].to_i }
                                   .filter_map do |r|
      po = account.mes_production_orders.find_by(id: r[:id])
      next if po.nil?

      who = User.where(id: po.ack_owner_ids).pluck(:name).join('、').presence || '⚠️ 没有任何人'
      format('%s｜%s｜等了 %d 工作小时 → %s', po.order_no,
             Mes::ProductionOrder::STAGE_LABELS[po.stage], r[:hours], who)
    end
    section('超时未接单的生产订单', '进了这一段却没人接，单子就停在那不动', rows)
  end

  def departed_owners
    gone = account.account_users.where.not(deactivated_at: nil).pluck(:user_id)
    return section('离职同事名下的遗留', '', []) if gone.empty?

    rows = account.mes_production_orders.where(owner_id: gone, status: 'IN_PROGRESS')
                  .includes(:owner).map do |po|
      format('生产订单 %s｜%s｜归属 %s（已离职）', po.order_no,
             Mes::ProductionOrder::STAGE_LABELS[po.stage], po.owner&.name)
    end
    account.crm_customers.where(account_owner_id: gone).group(:account_owner_id).count
           .each { |uid, n| rows << format('客户 %d 个仍挂在 %s（已离职）名下', n, User.find_by(id: uid)&.name) }
    section('离职同事名下的遗留', '人走了但单子/客户没交接，没人会去看', rows)
  end

  # 删用户时外键把 owner_id 置空，邮箱却照常收；密码早已停用 → 每轮认证失败刷日志。
  def ownerless_mail
    rows = account.crm_mail_accounts.where(owner_id: nil, is_active: true).map do |m|
      format('%s｜最后成功收信 %s', m.email_address,
             m.imap_synced_at&.strftime('%Y-%m-%d %H:%M') || '从未')
    end
    section('无主却仍在收信的邮箱', '收不到也没人知道，只会一直刷失败日志', rows)
  end

  def dead_board_owners
    bad = account.account_users.where.not(deactivated_at: nil).pluck(:user_id).to_set
    rows = account.mes_board_owners.filter_map do |b|
      dead = Array(b.manager_ids).select { |id| bad.include?(id) || !User.exists?(id) }
      next if dead.empty?

      format('MES 板块 %s（产线 %s）负责人含已离职/已删：%s', b.board_key,
             b.product_line.presence || '全部',
             User.where(id: dead).pluck(:name).join('、').presence || dead.join(','))
    end
    account.tiktok_departments.where.not(leader_id: nil).each do |d|
      next unless bad.include?(d.leader_id) || !User.exists?(d.leader_id)

      rows << format('TK 部门「%s」负责人已离职/已删', d.name)
    end
    section('指向离职者的负责人配置', '那一段的活会派给一个不在的人', rows)
  end

  def never_used_accounts
    rows = account.account_users.active_members.includes(:user).filter_map do |au|
      u = au.user
      next if u.nil? || u.sign_in_count.to_i.positive?

      format('%s｜%s｜建号 %s', u.name, u.email, u.created_at.strftime('%Y-%m-%d'))
    end
    section('建了从没登录过的账号', '占着各处选人列表，真人未必在用', rows)
  end

  def section(title, why, rows) = { title: title, why: why, rows: rows }
end
