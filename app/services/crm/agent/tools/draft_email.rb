# 起草邮件，存进草稿箱——**不发**。一次可以写一封，也可以给一批客户各写一封。
#
# 用户定的规矩：agent 只出草稿，发不发由人点。AI 把价格或交期写错了，
# 草稿还能改；直接发出去就收不回来了。
#
# ⚠️ 批量那条路（drafts）是 2026-10-24 生产上一次真失败逼出来的：
# 用户让给 9 个待跟进客户各发一封问候，模型逐个调了 9 次 find_customer + 9 次本工具，
# 一轮 16 次的预算在第 16 次被切断，**9 封只写成 7 封**。
# 一次传完就只花 1 次预算，剩下的留给真正需要查的事。
class Crm::Agent::Tools::DraftEmail < Crm::Agent::Tools::Base
  description '把写好的邮件存进草稿箱（不会发送）。' \
              '要给多个客户各写一封时，**必须用 drafts 一次传完**，不要反复调用本工具——' \
              '一轮的工具次数有限，逐封调用会在中途被切断、后面几封写不成。' \
              '写完后告诉用户去「邮件 → 草稿箱」检查并手动发送。'
  param :customer_id, type: 'integer', desc: '单封时用：这封邮件关联的客户ID', required: false
  param :subject, desc: '单封时用：邮件主题', required: false
  param :body, desc: '单封时用：邮件正文（纯文本，按客户的语言写）', required: false
  param :to_address, desc: '单封时用：收件人邮箱；不传就用客户档案上的联系邮箱', required: false
  param :drafts, type: 'array', required: false,
                 desc: '批量时用：[{customer_id, subject, body, to_address?}, …]，一次最多 20 封。' \
                       '每封的正文都要按该客户的语言分别写，不要复制同一段。'

  MAX_BATCH = 20

  def execute(customer_id: nil, subject: nil, body: nil, to_address: nil, drafts: nil)
    rows = Array(drafts).map { |d| symbolize(d) }
    rows = [{ customer_id: customer_id, subject: subject, body: body, to_address: to_address }] if rows.empty?
    return '要写的邮件是空的：给 customer_id/subject/body，或用 drafts 一次传多封。' if rows.compact.empty?
    return "一次最多 #{MAX_BATCH} 封，拆成几次调用（每次都用 drafts）。" if rows.size > MAX_BATCH

    results = rows.map { |row| draft_one(row) }
    rows.size == 1 ? single_text(results.first) : summarize(results)
  end

  private

  # 单封仍按原来那句话回：工具结果是直接给模型看的，返回 hash 它会原样念出来。
  def single_text(result)
    return result[:text] unless result[:ok]

    "已存成草稿：#{result[:text]}。" \
      '**还没有发送**，请到「邮件 → 草稿箱」检查无误后自己点发送。'
  end

  def symbolize(row)
    return {} unless row.respond_to?(:to_h)

    row.to_h.transform_keys { |k| k.to_s.to_sym }
  end

  # 每封独立成败：一封缺邮箱不该把其余几封一起带掉（逐封调用时本来就是各自独立的）。
  def draft_one(row)
    customer = scope.customers.find_by(id: row[:customer_id])
    return { ok: false, text: "看不到 ID #{row[:customer_id]} 这个客户，没法建草稿。" } if customer.nil?

    to = row[:to_address].presence || customer.contact_email.presence
    blocker = draft_blocker(customer, row, to)
    return { ok: false, text: blocker } if blocker

    save_draft(customer, row, to)
  end

  def draft_blocker(customer, row, to_address)
    return "#{customer.name}：档案里没有联系邮箱，这封没建。" if to_address.blank?
    return "#{customer.name}：主题或正文是空的，这封没建。" if row[:subject].blank? || row[:body].blank?

    nil
  end

  def save_draft(customer, row, to_address)
    draft = create_draft(customer, row[:subject], row[:body], to_address)
    # 这个 label 是前端那颗按钮上的字，别用 clip——它会缀上「（已截断）」，按钮里读着像报错。
    scope.record_artifact(kind: 'email_draft', id: draft.id, customer_id: customer.id,
                          label: "邮件草稿：#{row[:subject].to_s.strip.truncate(24)}")
    { ok: true, text: "#{customer.name}（草稿 #{draft.id}）→ #{to_address}" }
  end

  def summarize(results)
    ok = results.select { |r| r[:ok] }
    bad = results.reject { |r| r[:ok] }
    lines = ["已存 #{ok.size}/#{results.size} 封草稿（**都没有发送**）："]
    lines += ok.map { |r| "— #{r[:text]}" }
    lines << "\n没建成的 #{bad.size} 封：" if bad.any?
    lines += bad.map { |r| "— #{r[:text]}" }
    lines << '请到「邮件 → 草稿箱」逐封检查无误后自己点发送。'
    lines.join("\n")
  end

  def create_draft(customer, subject, body, to_address)
    scope.account.crm_emails.create!(
      owner_id: scope.user_id, crm_customer_id: customer.id,
      folder: 'DRAFT', send_status: 'DRAFT',
      subject: subject.to_s, body: body.to_s, to_address: to_address,
      email_date: Time.current
    )
  end
end
