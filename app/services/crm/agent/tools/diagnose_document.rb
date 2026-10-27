# 「这张单为什么做不了这件事」。
#
# 用户卡住时最常见的两种话术是「这单怎么出不了货」和「怎么没有编辑按钮」——
# 后者一条报错都没有。两种挡住他的其实是同一套判定，所以这里诊断的是**动作**，
# 不是报错文案。
#
# 事实全部来自 Mes::DocDiagnosis（只读、只调已有谓词），模型只负责把结果说成人话。
# ⚠️ 别让模型自己推断原因：它没查过库，会说出「可能是库存不足，建议补货」这种
# 听着专业、实际把人引到沟里的话——真实原因可能是「货在原料账上，要先转成成品」。
class Crm::Agent::Tools::DiagnoseDocument < Crm::Agent::Tools::Base
  description '诊断某张单据为什么做不了某个操作：卡在哪一步、下一步该谁动、那个人收到通知没有。' \
              '用户说「这单出不了货」「怎么没有审批按钮」「提交了没反应」「卡住了」时用这个。'
  param :doc_no, desc: '单号。销售订单 WT-/MO-/PO- 开头，出库单 DN- 开头，采购单 PU- 开头，出入库单 SE- 开头', required: true
  param :action, desc: '想做的操作，如 出库/审核/提交审批/接单/确认用料/下发采购/过账。说不清就不传，会把这张单上所有操作都过一遍', required: false

  def execute(doc_no:, action: nil)
    rec = Mes::DocDiagnosis.locate(scope.account, doc_no)
    return "没找到单号 #{doc_no}。确认一下单号对不对（销售订单 WT- 开头、出库单 DN- 开头、采购单 PU- 开头）。" if rec.nil?
    return '你没有权限查看这张单。' unless visible?(rec)

    d = Mes::DocDiagnosis.for(rec, account_user)
    return "认得这张单，但还不会诊断这类单据（#{rec.class.name.demodulize}）。" if d.nil?

    render(d.call(action), rec)
  end

  private

  def account_user = @account_user ||= scope.account.account_users.find_by(user_id: scope.user_id)

  # 可见性跟着已有口径走：出库单按客户范围，其余 MES 单据本来就是全员可见
  # （车间/仓管没有 CRM 角色，按 owner 过滤他们一张都看不到，见 Mes::BaseController）。
  def visible?(rec)
    return scope.shipments.exists?(id: rec.id) if rec.is_a?(Mes::Shipment)

    true
  end

  def render(res, rec)
    return res[:error] if res[:error]

    lines = ["【#{res[:doc_type] || '出库单'} #{res[:doc_no] || rec.try(:shipment_no)}】当前：#{res[:status_label]}"]
    lines << waiting_line(res[:waiting_on]) if res[:waiting_on]
    lines << notice_line(res[:notice]) if res[:notice]
    lines.concat(action_lines(res))
    lines << '若用户认为这是系统的毛病，可以用 report_issue 把问题连同上面这些现场一起提交。'
    lines.compact.join("\n")
  end

  # 出库诊断（Mes::ShipmentDiagnosis）返回的是单个动作，字段名略有不同，两种都认。
  def action_lines(res)
    rows = res[:actions] || [res]
    rows.map do |a|
      head = "· #{a[:action_label]}：#{a[:blocked] ? '现在做不了' : '现在可以做'}"
      body = Array(a[:blockers]).map { |b| "    - #{b[:text]}#{b[:fix] ? "（#{b[:fix]}）" : ''}" }
      [head, *body].join("\n")
    end
  end

  def waiting_line(waiting)
    # 待办就在提问人自己手上时 names 是故意空的（见 Mes::DocDiagnosis#waiting_on）。
    # 不先分出这一支，空 names 会被一律说成「没人负责、这张单会一直挂着」——
    # 一句假警报，模型照着就把「该你办」答成了系统故障。
    return "下一步：#{waiting[:label]}（就等你，不用找别人）" if waiting[:mine].present?

    names = Array(waiting[:names]).join('、')
    who = names.presence ? " —— #{names}" : '（系统里没查到该负责这一步的人，这张单会一直挂着）'
    "下一步：#{waiting[:label]}#{who}#{notified_suffix(waiting[:notified])}"
  end

  # 「该知道的人知不知道」——第三问。查不到通知、且那会儿这类通知已经能发了，
  # 才算系统的问题；单子比功能老就只是老，不是 bug。
  def notified_suffix(state)
    return '' if state.nil?
    return '（已通知到）' if state[:count].to_i.positive?
    return '【⚠️ 系统没给他们发过待办通知，他们可能不知道】' if state[:supported]

    '（这张单提交时系统还没有这类通知，所以没提醒过）'
  end

  def notice_line(notice) = notice && "提示：#{notice[:text]}#{notice[:fix] ? "（#{notice[:fix]}）" : ''}"
end
