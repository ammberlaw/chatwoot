# 收信后自动识别商机进度（对标小满「关键商机自动更新」）：AI 读该客户最近往来，
# 若【最新来信】报告了具体业务进度（定金/生产/发货/提单/尾款/客诉等），就在客户时间线写一条
# 跟进记录（source=AI）。只写 journal、不自动改商机阶段（阶段变更仍由业务员确认，避免误判）。
# 仅处理已关联客户的来信；AI 未配置则静默跳过；幂等：同一封信不重复建记录。
class Crm::EmailProgressJob < ApplicationJob
  queue_as :low

  CONTEXT_LIMIT = 8 # 取最近几封往来做上下文

  def perform(email_id)
    email = Crm::Email.find_by(id: email_id)
    return if email.nil? || email.crm_customer_id.blank?
    return unless email.folder == 'INBOX' # 只对客户来信识别进度
    return if Crm::FollowUpNote.exists?(source_email_id: email.id) # 幂等

    customer = Crm::Customer.find_by(id: email.crm_customer_id)
    return if customer.nil?

    result = Crm::EmailAiService.new(account: email.account)
                                .extract_progress(transcript: build_transcript(email, customer))
    return unless result['update']

    title = result['title'].to_s.strip
    return if title.blank?

    Crm::FollowUpNote.create!(
      account_id: email.account_id,
      crm_customer_id: customer.id,
      crm_opportunity_id: primary_opportunity_id(customer),
      owner_id: customer.account_owner_id,
      contact_id: email.contact_id,
      title: title,
      body: result['body'].to_s.strip.presence,
      follow_up_method: 'EMAIL',
      source: 'AI',
      source_email_id: email.id
    )
  rescue Crm::EmailAiService::NotConfigured
    nil # 进度识别必须靠 AI，未配置就跳过
  rescue StandardError => e
    Rails.logger.warn("[Crm::EmailProgressJob] email=#{email_id} #{e.class}: #{e.message}")
  end

  private

  # 优先挂到进行中的商机，否则最近更新的商机；都没有则留空（记录仍挂在客户上）。
  def primary_opportunity_id(customer)
    (customer.opportunities.open_stages.order(updated_at: :desc).first ||
      customer.opportunities.order(updated_at: :desc).first)&.id
  end

  # 最近往来拼成 transcript（时间/方向/主题/正文节选），最新来信排在最后。
  def build_transcript(email, customer)
    emails = customer.emails.where.not(folder: 'DRAFT')
                     .order(email_date: :desc).limit(CONTEXT_LIMIT).to_a.reverse
    emails << email unless emails.any? { |e| e.id == email.id }
    lines = emails.map do |e|
      dir = %w[SENT BULK].include?(e.folder) ? '我方→对方' : '对方→我方'
      date = e.email_date&.strftime('%Y-%m-%d') || '未知日期'
      body = e.body.to_s.gsub(/\s+/, ' ').strip[0, 500]
      "[#{date}] #{dir} 主题：#{e.subject}\n#{body}"
    end
    "客户：#{customer.name}\n\n#{lines.join("\n\n")}"
  end
end
