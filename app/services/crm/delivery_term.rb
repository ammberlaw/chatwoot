# 从 PI 条款里把交期读出来。
#
# 交期这件事一直都在，只是没人把它当字段存过：生产 206 张 PI 里 178 张（86%）在
# terms 里写着「Delivery time: 30 working days after receiving the payment」，
# 其中 164 张就是这一句原话，变体只有天数不同（7 / 10 / 15 / 20）。
# 人看得懂，系统读不懂——于是 122 张在途订单里 102 张（84%）查不到交期，
# 客户问「我的货什么时候出」只能去问生产。
#
# 所以这里**不是让业务员多填一个字段**（这个系统里凡是要人额外填的最后都是空的），
# 而是把他本来就写了二十遍的那句话解析出来。
class Crm::DeliveryTerm
  Parsed = Struct.new(:days, :working_days, :phrase, keyword_init: true)

  # 必须锚定在「delivery time」后面才取数字：条款里还有付款条款，
  # 那里的「30 days」说的是账期，不是交期，抓错了会把交期算成另一回事。
  #
  # 覆盖实测到的全部写法：
  #   delivery time: 30 working days after receiving the payment
  #   deliverytime: about 7 working days after receipt of your prepaid payment
  #   delivery time: 5-7working days after receiving the payment   ← 没空格
  #   deliverytime: about 6 days after receipt                     ← 自然日
  PATTERN = /deliver\w*\s*time\s*[:：]?\s*(?:about\s+)?(\d+)\s*(?:[-–~]\s*(\d+))?\s*(working\s*)?days/i

  # 解析不出来就返回 nil——宁可留空，也不编一个日期。
  # 交期是对客户的承诺，猜错了比没有更糟。
  def self.parse(terms)
    match = PATTERN.match(terms.to_s)
    return nil if match.nil?

    # 写成区间（5-7 working days）时取**上限**：对外承诺的是最晚那天。
    days = [match[1].to_i, match[2].to_i].max
    return nil unless days.positive?

    Parsed.new(days: days, working_days: match[3].present?, phrase: match[0].strip)
  end

  # 从起点算出预计出货日。起点是「收款日」——PI 一改成已付款就自动转销售订单
  # （见 Crm::PiToSalesOrder），所以转单日就是收款日的近似。
  def self.due_from(terms, start_at)
    parsed = parse(terms)
    return nil if parsed.nil? || start_at.blank?

    add_days(start_at.to_date, parsed.days, parsed.working_days)
  end

  # ⚠️ 工作日只跳周末，**不跳法定节假日**。系统里没有节假日表，编一份出来
  # 会在春节、国庆这种长假上错得离谱（春节能差一整周）。
  # 宁可算早一点让人提前看到，也不假装精确。
  def self.add_days(date, count, working)
    return date + count unless working

    result = date
    count.times { result = next_workday(result) }
    result
  end

  def self.next_workday(date)
    result = date + 1
    result += 1 while result.saturday? || result.sunday?
    result
  end
end
