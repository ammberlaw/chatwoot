# 官网上的增值税号 → 欧盟官方验一道。
#
# 这是背调三方证据里唯一**官方**的那一方：
#   官网是对方自己写的、Apollo 是第三方推测的，只有 VIES 说的是「这个号现在确实登记在册」。
# 空壳公司和注销掉的公司在这一步露馅。
#
# 验不过的**不丢掉、照样返回**——官网上印着一个验不过的税号本身就是信号，
# 比查不到更值得业务员看一眼。但绝不会把没验过的号写进客户档案（见 Crm::LeadToCustomer）。
class Crm::VatLookup
  # 返回 { number: 'DE129273283', status: 'valid'|'invalid', name:, address: }，
  # 一个像样的候选都没有、或者撞上 VIES 限流时返回 nil（限流不是「号是假的」）。
  def self.for(site_text, domain: nil)
    first_invalid = nil
    Crm::VatNumber.extract(site_text, domain: domain).each do |country, number|
      result = Crm::ViesClient.check(country, number).merge(number: "#{country}#{number}")
      return result if result[:status] == 'valid'

      first_invalid ||= result if result[:status] == 'invalid'
    end
    first_invalid
  end
end
