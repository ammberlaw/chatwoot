# 某个客户的跟进记录。
#
# 电话、微信、见面、展会上聊的都记在这儿，邮件里**没有**——
# customer_emails 只看得到往来邮件，问「上次跟这家聊到哪了」光翻邮件会漏掉一半，
# 而真正松口的那句话往往就是电话里说的。
class Crm::Agent::Tools::FollowUpNotes < Crm::Agent::Tools::Base
  description '查某个客户的跟进记录（电话、微信、会面、展会这些线下沟通，邮件里查不到）。问「上次聊到哪」「客户什么态度」时，除了邮件也要看这个。先用 find_customer 拿到客户ID。'
  param :customer_id, type: 'integer', desc: '客户ID'
  param :limit, type: 'integer', desc: '最多取几条，默认 12，上限 30', required: false

  # 跟进笔记正文一般几句话，但也有人把整段微信记录粘进来。
  BODY_CLIP = 500

  WAYS = { 'EMAIL' => '邮件', 'PHONE' => '电话', 'MEETING' => '会面',
           'WHATSAPP' => 'WhatsApp', 'WECHAT' => '微信' }.freeze
  TAGS = { 'INTERESTED' => '有意向', 'WAITING_CUSTOMER' => '等客户回话',
           'WAITING_INTERNAL' => '等内部处理', 'INVALID' => '无效' }.freeze

  def execute(customer_id:, limit: 12)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户（可能不在你的权限范围内，或者 ID 不对）。" if customer.nil?

    rows = scope.follow_up_notes.where(crm_customer_id: customer.id)
                .order(created_at: :desc, id: :desc).limit([limit.to_i, 30].min)
    return "#{customer.name} 名下没有你能看到的跟进记录（线下沟通可能没人录）。" if rows.empty?

    "【#{customer.name} 的跟进记录】按时间倒序，共列 #{rows.size} 条：\n#{rows.map { |n| render(n) }.join("\n")}"
  end

  private

  def render(note)
    "— #{day(note.created_at)}｜#{WAYS[note.follow_up_method] || '方式未填'}｜" \
      "#{TAGS[note.result_tag] || '无结果标签'}｜录入 #{note.owner&.name || '—'}#{ai_mark(note)}\n  " \
      "#{note.title}#{body_line(note)}"
  end

  # AI 从邮件自动识别出来的那批要标出来：它是机器读出来的结论，
  # 可信度和业务员自己打完电话手写的那条不一样。
  def ai_mark(note) = note.source == 'AI' ? '（AI 从邮件识别）' : ''

  def body_line(note)
    text = clip(note.body, BODY_CLIP)
    text.blank? ? '' : "\n  #{text}"
  end
end
