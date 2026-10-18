# 报价单和定制询价申请的「单据状态」。
#
# 和 quote_history 分工清楚：那个查**价**（这家以前报过多少钱），
# 这个查**单**（哪几张发出去还没回、哪张明天就过期了、找主管要的价报回来了没）。
#
# 两张单据语义不同，一次都给，省一次来回：
# · 报价单 crm_quotes：发给客户的正式报价，DRAFT→SENT→CONFIRMED，带有效期。
# · 定制询价申请 crm_quote_requests：业务员填参数找主管要价的内部单，PENDING→QUOTED。
class Crm::Agent::Tools::Quotes < Crm::Agent::Tools::Base
  description '查报价单和定制询价申请的状态：哪些发给客户了还没确认、哪些快过期或已过期、找主管要的定制价报回来了没。可按客户ID或单号查；都不给就列未结的那些。'
  param :customer_id, type: 'integer', desc: '客户ID，查这个客户的报价单', required: false
  param :doc_no, desc: '单号关键词（QT- 开头是报价单，QR- 开头是询价申请）', required: false
  param :only_open, type: 'boolean', desc: '只看未结的（报价单草稿/已发出、询价申请待报价），默认 true', required: false
  param :limit, type: 'integer', desc: '每类最多列几条，默认 12，上限 30', required: false

  QUOTE_STATUSES = { 'DRAFT' => '草稿', 'SENT' => '已发给客户', 'CONFIRMED' => '客户已确认', 'EXPIRED' => '已过期' }.freeze
  REQ_STATUSES = { 'PENDING' => '等主管报价', 'QUOTED' => '已报价', 'CANCELLED' => '已取消' }.freeze

  def execute(customer_id: nil, doc_no: nil, only_open: true, limit: 12)
    n = limit.to_i.positive? ? [limit.to_i, 30].min : 12
    blocks = [quote_block(customer_id, doc_no, only_open, n),
              request_block(customer_id, doc_no, only_open, n)].compact_blank
    return '没查到你能看到的报价单或定制询价申请。' if blocks.empty?

    blocks.join("\n\n")
  end

  private

  def quote_block(customer_id, doc_no, only_open, limit)
    rows = scope.quotes
    rows = rows.where(crm_customer_id: customer_id.to_i) if customer_id.present?
    rows = rows.where('quote_no ILIKE ?', "%#{doc_no.to_s.strip}%") if doc_no.present?
    rows = rows.pending if only_open && doc_no.blank?
    rows = rows.order(quote_date: :desc, id: :desc).limit(limit).to_a
    return nil if rows.empty?

    "【报价单】共列 #{rows.size} 张：\n#{rows.map { |q| quote_line(q) }.join("\n")}"
  end

  def quote_line(quote)
    "— #{quote.quote_no}｜#{quote.crm_customer&.name || '客户未挂'}｜#{clip(quote.name, 40)}｜" \
      "#{money(quote.total_amount_micros, quote.quote_currency.presence || 'USD')}｜" \
      "#{QUOTE_STATUSES[quote.status] || quote.status}｜报价日 #{day(quote.quote_date)}｜#{validity(quote.valid_until)}"
  end

  def request_block(customer_id, doc_no, only_open, limit)
    rows = scope.quote_requests
    rows = rows.where(crm_customer_id: customer_id.to_i) if customer_id.present?
    rows = rows.where('request_no ILIKE ?', "%#{doc_no.to_s.strip}%") if doc_no.present?
    rows = rows.pending if only_open && doc_no.blank?
    rows = rows.order(created_at: :desc, id: :desc).limit(limit).to_a
    return nil if rows.empty?

    "【定制询价申请】共列 #{rows.size} 张：\n#{rows.map { |r| request_line(r) }.join("\n")}"
  end

  def request_line(req)
    "— #{req.request_no}｜#{clip(req.title, 40)}｜#{req.product_line}｜#{req_customer(req)}｜" \
      "数量 #{req.quantity || '—'}｜#{REQ_STATUSES[req.status] || req.status}｜" \
      "#{quoted_price(req)}｜#{req_people(req)}｜#{validity(req.valid_until)}"
  end

  def req_customer(req) = req.crm_customer&.name || '客户未挂'

  def req_people(req)
    "申请人 #{req.applicant&.name || '—'}｜报价人 #{req.pricer&.name || '未指定'}"
  end

  def quoted_price(req)
    return '还没报价' if req.quoted_price_micros.blank?

    "报价 #{money(req.quoted_price_micros, req.quote_currency.presence || 'USD')}"
  end

  # 有效期是业务员最该被提醒的那一格：过期的报价客户拿着来下单就得重新核价，
  # 所以过期/将到期都算出天数直接摆出来，别让人自己去减日期。
  def validity(valid_until)
    return '未设有效期' if valid_until.blank?

    days = (valid_until.to_date - Time.zone.today).to_i
    return "已过期 #{-days} 天（#{day(valid_until)}）" if days.negative?
    return "今天到期（#{day(valid_until)}）" if days.zero?

    "还有 #{days} 天到期（#{day(valid_until)}）"
  end
end
