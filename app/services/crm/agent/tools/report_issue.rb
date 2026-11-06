# 用户觉得「这是系统的毛病」时，把问题连同**提交那一刻的现场**一起存下来，
# 并给管理员发一条站内通知。
#
# 关键不在用户写了什么，而在现场。一句「出不了货」和发微信截图没区别——修的人
# 还得从头把状态重建一遍。把单号、状态、诊断跑出来的阻碍、该谁动、通知发没发、
# 提交人的角色一起存下来，打开就能直接动手。
#
# ⚠️ 不替用户判断是不是 bug。用户说是就记下来，真伪由看的人判断——
# 让 AI 先判一道，等于给「其实是真 bug」的那些加一层掩盖
# （2026-10-23/24 查实：报上来的六个问题，六个都是真 bug）。
class Crm::Agent::Tools::ReportIssue < Crm::Agent::Tools::Base
  writes_data

  description '把用户反映的系统问题提交给管理员。用户说「这是不是 bug」「系统有问题」' \
              '「帮我报一下」「报给管理员」时**一律直接调这个**，不要先自己判断算不算 bug、' \
              '也不要求他先提供单号或截图——判断真伪是看报告的人的事。' \
              '手头有单号时顺手传上，诊断现场会一并存下来；没有单号照样提交。'
  param :body, desc: '用户描述的问题，尽量用他自己的话', required: true
  param :doc_no, desc: '相关单号，没有就不传', required: false
  param :action, desc: '他想做而做不了的操作，如 出库/审批/接单', required: false

  def execute(body:, doc_no: nil, action: nil)
    text = body.to_s.strip
    return '请把问题描述一下再提交。' if text.length < 4

    rec = doc_no.present? ? Mes::DocDiagnosis.locate(scope.account, doc_no) : nil
    dup = open_duplicate(rec, action)
    return already_reported(dup) if dup

    report = create_report(text, rec, action)
    notify_admins(report, rec)
    "已提交（编号 ##{report.id}）#{rec ? "，并记下了 #{report.subject_no} 当时的状态" : ''}。管理员会收到站内通知。"
  end

  private

  def create_report(text, rec, action)
    scope.account.crm_issue_reports.create!(
      reporter_id: scope.user_id, body: text, action_type: action.presence,
      subject_type: rec&.class&.name, subject_id: rec&.id,
      subject_no: rec && doc_number(rec), context: snapshot(rec, action)
    )
  end

  # 同一张单的同一个动作已经报过、还没处理完，就不再开一张。
  # 一处配置坏了往往是十个人同时撞上，各报一张会把管理员的通知刷成一片，
  # 真正的那条反而被埋掉。只有挂到具体单据的才去重——不挂单的问题五花八门，
  # 「找不到台账」和「页面白屏」看着一样但不是一回事。
  def open_duplicate(rec, action)
    return nil if rec.nil?

    scope.account.crm_issue_reports.open_ones.recent_first
         .find_by(subject_type: rec.class.name, subject_id: rec.id, action_type: action.presence)
  end

  def already_reported(dup)
    who = dup.reporter_id == scope.user_id ? '你' : (dup.reporter&.name || '同事')
    "这个问题已经报过了（编号 ##{dup.id}，#{who} 在 #{dup.created_at.strftime('%m-%d %H:%M')} 提的，" \
      '还在处理中），没有重复提交。管理员那边看到的就是这一条。'
  end

  def doc_number(rec)
    rec.try(:order_no) || rec.try(:shipment_no) || rec.try(:po_no) || rec.try(:entry_no)
  end

  def account_user = @account_user ||= scope.account.account_users.find_by(user_id: scope.user_id)

  # 现场：诊断结论 + 提交人身份。诊断失败不能把提交也拖垮——问题本身比现场更重要。
  def snapshot(rec, action)
    base = { reported_at: Time.current.iso8601, reporter: reporter_snapshot }
    return base if rec.nil?

    base.merge(diagnosis: Mes::DocDiagnosis.for(rec, account_user)&.call(action))
  rescue StandardError => e
    base.merge(diagnosis_error: "#{e.class}: #{e.message}")
  end

  def reporter_snapshot
    { name: scope.user&.name, mes_roles: account_user&.effective_mes_roles,
      crm_role: account_user&.crm_role, admin: account_user&.administrator? }
  end

  # 发给管理员和副管。用已有的系统通知通道（团队协同），不另造一套。
  def notify_admins(report, rec)
    targets = admin_user_ids
    return if targets.blank?

    sender = Crm::SystemUser.for(scope.account)
    text = notify_text(report)
    targets.each do |uid|
      Chat::NotifyService.new(account: scope.account, sender: sender)
                         .notify(uid, text, ref: ref_for(report, rec))
    end
  rescue StandardError => e
    # 通知发不出去不该让提交失败——问题已经存下来了，这才是主要的。
    Rails.logger.warn("[IssueReport] notify failed report=#{report.id}: #{e.message}")
  end

  def admin_user_ids
    scope.account.account_users.active_members
         .select { |au| au.administrator? || au.crm_deputy_admin? }
         .map(&:user_id) - [scope.user_id]
  end

  # 通知正文要**自带结论**。团队沟通的单据卡片只认前端配过路由的几种类型，
  # issue_report 不在里面——卡片不会渲染，管理员能看到的就只有这段文字。
  # 光写一句用户原话等于把考古工作留给看的人，所以把「哪张单、什么状态、
  # 第一条阻碍、在等谁」一并写进去，打开通知就知道该不该动手。
  # 现场摘要取 Crm::IssueReport#diagnosis_summary——「问题反馈」页用的是同一份，
  # 管理员在通知里看到的和点进去看到的必须一致。
  def notify_text(report)
    sum = report.diagnosis_summary
    lines = ["【问题反馈】#{scope.user&.name} 提交：#{clip(report.body, 120)}"]
    lines << doc_line(report, sum) if report.subject_no.present?
    lines << "当前：#{sum[:status_label]}" if sum[:status_label]
    lines << "卡在：#{sum[:blocker]}" if sum[:blocker]
    lines << waiting_line(sum[:waiting]) if sum[:waiting]
    lines.join("\n")
  end

  # 单据类型取诊断给的那个，不取用户原话里的——模型转述时会把出库单写成销售订单，
  # 看报告的人照着去错板块里找。
  def doc_line(report, sum)
    want = report.action_type.presence ? "（想做：#{report.action_type}）" : ''
    "单据：#{[sum[:doc_type], report.subject_no].compact_blank.join(' ')}#{want}"
  end

  def waiting_line(waiting)
    who = waiting[:names].join('、').presence || '系统里没查到该负责这一步的人'
    base = "等：#{waiting[:label]}（#{who}）"
    waiting[:notified] == false ? "#{base}⚠️ 系统没给他们发过通知" : base
  end

  def ref_for(report, rec)
    return nil if rec.nil?

    { type: 'issue_report', id: report.id, label: '问题反馈',
      title: report.subject_no.to_s, subtitle: "#{scope.user&.name} · 待查" }
  end
end
