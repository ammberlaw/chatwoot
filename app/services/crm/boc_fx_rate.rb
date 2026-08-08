# 抓取中国银行外汇牌价（现汇买入价），upsert 到 crm_fx_rates。
# 中行主牌价页仅含「当天」牌价，故按日快照累积历史；外币订单锁定做单当日汇率。
# 页面表格列序：货币名称 | 现汇买入价 | 现钞买入价 | 现汇卖出价 | 现钞卖出价 | 中行折算价 | 发布日期 | 发布时间
# 现汇买入价以「每 100 单位外币」报价，折算汇率 = 现汇买入价 / 100。
class Crm::BocFxRate
  URL = 'https://www.boc.cn/sourcedb/whpj/'.freeze
  # 中行「货币名称」→ 系统币种（只取 CRM 用到的外币，见 Crm::Customer::CURRENCIES）
  NAME_MAP = { '美元' => 'USD', '欧元' => 'EUR' }.freeze
  UNIT = 100.0 # 现汇买入价按每 100 单位报价

  def self.sync!
    new.sync!
  end

  # 返回成功入库的币种数。
  def sync!
    doc = Nokogiri::HTML(fetch_html)
    doc.css('table tr').sum do |tr|
      cells = tr.css('td').map { |td| td.text.strip }
      upsert_row(cells) ? 1 : 0
    end
  end

  private

  def upsert_row(cells)
    return false if cells.length < 7

    currency = NAME_MAP[cells[0]]
    return false unless currency

    spot_buy = cells[1].to_f
    return false unless spot_buy.positive?

    published_raw = cells[6] # 发布日期，形如 "2026/08/08 10:30:00"
    row = Crm::FxRate.find_or_initialize_by(currency: currency, quote_date: parse_date(published_raw))
    row.rate = spot_buy / UNIT
    row.source = 'BOC'
    row.published_at = parse_time(published_raw)
    row.save!
    true
  end

  def fetch_html
    conn = Faraday.new do |f|
      f.options.timeout = 20
      f.options.open_timeout = 10
    end
    resp = conn.get(URL) { |req| req.headers['User-Agent'] = 'Mozilla/5.0' }
    resp.body.dup.force_encoding('UTF-8')
  end

  # "2026/08/08 10:30:00" / "2026/08/08" → Date；解析失败退当天。
  def parse_date(raw)
    Date.parse(raw)
  rescue ArgumentError, TypeError
    Time.zone.today
  end

  def parse_time(raw)
    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end
end
