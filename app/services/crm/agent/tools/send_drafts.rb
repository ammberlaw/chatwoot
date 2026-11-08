# 把草稿**真的发出去**。
#
# 🔴 这是 agent 唯一一个会往公司外面发东西的动作。原来的规矩是「只出草稿，发不发由人点」，
# 2026-11-08 用户改成两步：**AI 写草稿 → 人看过 → 人开口说发 → AI 发**。
# 人那一句话就是闸门，所以这个工具**只在用户明确要求发送时调用**，
# 不能因为「草稿写完了顺手发一下」自己决定发。
#
# 默认只发**这一轮自己写的那几封**。不给「发草稿箱里所有的」这条路：
# 草稿箱里常年躺着别的东西（写了一半的报价、上个月没发完的跟进），
# 一句「批量发送」把它们一起寄出去是收不回来的事故。
class Crm::Agent::Tools::SendDrafts < Crm::Agent::Tools::Base
  writes_data

  description '把邮件草稿真正发送出去。**只有用户明确说了「发送/发出去/可以发」之类的话才能调用**，' \
              '不要自己决定发。默认发这一轮刚写的那几封；用户指名发某几封时传 draft_ids。'
  param :draft_ids, desc: '要发的草稿ID，多个用逗号隔开。不传＝发这一轮刚写的那几封', required: false

  # 一次最多发几封。和 DraftEmail 的批量上限对齐。
  MAX_SEND = 20

  def execute(draft_ids: nil)
    drafts = resolve(draft_ids)
    return '这一轮没有写过草稿。要发哪几封，把草稿ID告诉我。' if drafts.empty?
    return "一次最多发 #{MAX_SEND} 封，分几次来。" if drafts.size > MAX_SEND

    results = drafts.map { |draft| send_one(draft) }
    render(results)
  end

  private

  # 没指定就用这一轮记下的草稿（见 DraftEmail#save_draft 挂的 artifact）。
  def resolve(ids)
    wanted = ids.to_s.scan(/\d+/).map(&:to_i)
    wanted = scope.artifacts.select { |a| a[:kind] == 'email_draft' }.pluck(:id) if wanted.empty?
    return [] if wanted.empty?

    # 只发自己的、还是草稿的。别人的邮件、已经发过的，一律不碰。
    scope.account.crm_emails.where(id: wanted, owner_id: scope.user_id,
                                   folder: 'DRAFT', send_status: 'DRAFT').to_a
  end

  def send_one(draft)
    to = draft.to_address
    Crm::EmailSendService.new(email: draft).perform
    draft.reload
    { ok: draft.send_status == 'SENT', to: to, subject: draft.subject.to_s.truncate(24),
      error: draft.send_error }
  end

  def render(results)
    sent = results.select { |r| r[:ok] }
    failed = results.reject { |r| r[:ok] }
    lines = ["已发出 #{sent.size} 封#{failed.any? ? "，#{failed.size} 封没发出去" : ''}："]
    lines += sent.map { |r| "· #{r[:to]}｜#{r[:subject]}" }
    # 失败的要点名并带原因：报个总数等于让人自己去草稿箱一封封数。
    lines += failed.map { |r| "✗ #{r[:to]}｜#{r[:subject]}｜#{r[:error].to_s.truncate(40)}" }
    lines << '没发出去的还在草稿箱里，修好之后可以再让我发。' if failed.any?
    lines.join("\n")
  end
end
