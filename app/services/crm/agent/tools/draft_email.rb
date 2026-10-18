# 起草一封邮件，存进草稿箱——**不发**。
#
# 用户定的规矩：agent 只出草稿，发不发由人点。AI 把价格或交期写错了，
# 草稿还能改；直接发出去就收不回来了。
class Crm::Agent::Tools::DraftEmail < Crm::Agent::Tools::Base
  description '把写好的邮件存进草稿箱（不会发送）。写完后告诉用户去「邮件 → 草稿箱」检查并手动发送。'
  param :customer_id, type: 'integer', desc: '这封邮件关联的客户ID'
  param :subject, desc: '邮件主题'
  param :body, desc: '邮件正文（纯文本，按客户的语言写）'
  param :to_address, desc: '收件人邮箱；不传就用客户档案上的联系邮箱', required: false

  def execute(customer_id:, subject:, body:, to_address: nil)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户，没法建草稿。" if customer.nil?

    to = to_address.presence || customer.contact_email.presence
    return "#{customer.name} 的档案里没有联系邮箱，请在参数里给出收件人。" if to.blank?

    draft = create_draft(customer, subject, body, to)
    # 这个 label 是前端那颗按钮上的字，别用 clip——它会缀上「（已截断）」，按钮里读着像报错。
    scope.record_artifact(kind: 'email_draft', id: draft.id, customer_id: customer.id,
                          label: "邮件草稿：#{subject.to_s.strip.truncate(24)}")
    "已存成草稿（#{draft.id}）：收件人 #{to}，主题「#{subject}」。" \
      '**还没有发送**，请到「邮件 → 草稿箱」检查无误后自己点发送。'
  end

  private

  def create_draft(customer, subject, body, to_address)
    scope.account.crm_emails.create!(
      owner_id: scope.user_id, crm_customer_id: customer.id,
      folder: 'DRAFT', send_status: 'DRAFT',
      subject: subject.to_s, body: body.to_s, to_address: to_address,
      email_date: Time.current
    )
  end
end
