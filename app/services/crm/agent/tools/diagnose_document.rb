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
  param :doc_no, desc: '单号，原样传用户给的。生产任务单 WT-/MO- 开头，出库单 DN-，采购单 PU-/PO-，' \
                       '出入库单 SE-，退料单 RT-，CRM 销售订单 SO-，报价单 QT-，PI 的号是客户给的各式各样。' \
                       '**前缀认不出来也照样传**，工具会在所有单据里找一遍。', required: true
  param :action, desc: '想做的操作，如 出库/审核/提交审批/接单/确认用料/下发采购/过账。说不清就不传，会把这张单上所有操作都过一遍', required: false

  def execute(doc_no:, action: nil)
    rec = Mes::DocDiagnosis.locate(scope.account, doc_no)
    return outside_mes(doc_no) if rec.nil?
    return '你没有权限查看这张单。' unless visible?(rec)

    d = Mes::DocDiagnosis.for(rec, account_user)
    return "认得这张单，但还不会诊断这类单据（#{rec.class.name.demodulize}）。" if d.nil?

    render(d.call(action), rec)
  end

  private

  # MES 诊断管不到的单：CRM 销售订单、报价单、PI。
  #
  # 原来这里一句「没找到，销售订单 WT- 开头」就打发了——而 crm_sales_orders 有 592 张
  # 单全是 **SO-** 开头。2026-10-22 生产上有人问「SO-20261017-02 为什么转单库存为0」，
  # 得到的回答是他自己的单号格式不对。答错比答不出来糟得多：他会去改一个本来就对的东西。
  #
  # 这几类没有动作判定可跑（卡不卡在于审批和业务，不是单据状态机），
  # 所以只认出来是什么、什么状态、归谁，再指一条往下问的路。
  def outside_mes(doc_no)
    number = doc_no.to_s.strip
    hit = scope.sales_orders.find_by(order_no: number) ||
          scope.quotes.find_by(quote_no: number) ||
          scope.pis.find_by(pi_no: number)
    return not_found(number) if hit.nil?

    describe_crm_doc(hit, number)
  end

  def describe_crm_doc(hit, number)
    owner = User.find_by(id: hit.try(:owner_id))&.name
    bits = ["【#{crm_doc_label(hit)} #{number}】这张单在 CRM 这边，不是 MES 的生产/出库流程，所以没有「卡在哪一步」可诊断。"]
    bits << "状态：#{hit.try(:status) || '—'}#{approval_bit(hit)}"
    bits << "归属：#{owner}" if owner
    bits << '要看它转生产/出库之后的进度，用 order_progress；要看金额和明细，用 customer_profile。'
    bits.join("\n")
  end

  def approval_bit(hit)
    hit.respond_to?(:approval_status) && hit.approval_status.present? ? "　审批：#{hit.approval_status}" : ''
  end

  def crm_doc_label(hit)
    { 'SalesOrder' => '销售订单', 'Quote' => '报价单', 'Pi' => 'PI' }[hit.class.name.demodulize] || '单据'
  end

  # 认不出来时别乱指格式：系统里 PI 的号是客户给的，什么样的都有。
  def not_found(number)
    "没找到单号 #{number}，你能看到的范围里也没有。" \
      '确认一下是不是抄错了，或者这张单归别人、不在你的可见范围内。'
  end

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
