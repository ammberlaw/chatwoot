# 从公司官网正文里把欧盟增值税号（VAT / USt-IdNr / TVA / P.IVA）抠出来。
#
# 为什么能抠得到：欧盟各国都强制商业网站公示它。德国《电信媒体法》第 5 条要求
# Impressum 上写 USt-IdNr，意大利要写 Partita IVA，法国要写 TVA intracommunautaire。
# 背调本来就优先抓这几个法律信息页（见 Crm::CompanyLookupService::SUB_PAGE_PATTERNS），
# 号就印在那上面，只是以前没人去读。
#
# 这里**只负责找出长得像的**，真假交给 VIES 判（Crm::ViesClient）。
# 所以宁可多抠几个候选，也不要为了「精确」漏掉真的那个——
# 反正官方接口会把假的挡掉，而我们绝不把没验过的号写进客户档案。
class Crm::VatNumber
  # 各国税号去掉国家码之后的**格式**。
  #
  # ⚠️ 只校验长度是不够的：官网正文里混着网址，「...de/videofile...」会被当成
  # 德国税号 DEVIDEOFILE（2026-11-07 实测 DATA MODUL 就是这么中招的）。
  # 绝大多数成员国的税号是纯数字，只有少数几个位置上有字母——按真实格式卡死。
  FORMATS = {
    'AT' => /\AU\d{8}\z/, 'BE' => /\A\d{10}\z/, 'BG' => /\A\d{9,10}\z/,
    'CY' => /\A\d{8}[A-Z]\z/, 'CZ' => /\A\d{8,10}\z/, 'DE' => /\A\d{9}\z/,
    'DK' => /\A\d{8}\z/, 'EE' => /\A\d{9}\z/, 'EL' => /\A\d{9}\z/,
    'ES' => /\A[A-Z0-9]\d{7}[A-Z0-9]\z/, 'FI' => /\A\d{8}\z/,
    'FR' => /\A[A-Z0-9]{2}\d{9}\z/, 'HR' => /\A\d{11}\z/, 'HU' => /\A\d{8}\z/,
    'IE' => /\A(\d{7}[A-Z]{1,2}|\d[A-Z0-9+*]\d{5}[A-Z])\z/, 'IT' => /\A\d{11}\z/,
    'LT' => /\A(\d{9}|\d{12})\z/, 'LU' => /\A\d{8}\z/, 'LV' => /\A\d{11}\z/,
    'MT' => /\A\d{8}\z/, 'NL' => /\A\d{9}B\d{2}\z/, 'PL' => /\A\d{10}\z/,
    'PT' => /\A\d{9}\z/, 'RO' => /\A\d{2,10}\z/, 'SE' => /\A\d{12}\z/,
    'SI' => /\A\d{8}\z/, 'SK' => /\A\d{10}\z/, 'XI' => /\A(\d{9}|\d{12})\z/
  }.freeze

  # 候选长度（用来从粘着正文的串里切出来）。长度对不上的直接扔，
  # 省掉一次 VIES 调用——它有并发限流。
  LENGTHS = {
    'AT' => [9], 'BE' => [10], 'BG' => [9, 10], 'CY' => [9], 'CZ' => [8, 9, 10],
    'DE' => [9], 'DK' => [8], 'EE' => [9], 'EL' => [9], 'ES' => [9],
    'FI' => [8], 'FR' => [11], 'HR' => [11], 'HU' => [8], 'IE' => [8, 9],
    'IT' => [11], 'LT' => [9, 12], 'LU' => [8], 'LV' => [11], 'MT' => [8],
    'NL' => [12], 'PL' => [10], 'PT' => [9], 'RO' => (2..10).to_a, 'SE' => [12],
    'SI' => [8], 'SK' => [10], 'XI' => [9, 12]
  }.freeze

  # 分隔符：官网上写法五花八门，「DE 129 273 283」「IT-00743110157」
  # 「FR‑40303265045」（非断行连字符 U+2011）都见过，各种破折号全收。
  SEP = '[[:space:].\u2010-\u2015\-]'.freeze
  SEP_RE = /#{SEP}/
  PATTERN = /\b(#{LENGTHS.keys.join('|')})#{SEP}{0,2}((?:[0-9A-Za-z]#{SEP}{0,2}){6,16})/

  # 税号关键词。前面挨着这些词的才是真的——「Tel. DE 030 1234567」这种
  # 长得一模一样，不排序的话会白白耗掉一次 VIES 调用（它有并发限流）。
  KEYWORDS = /ust[\s.\-]?id|umsatzsteuer|steuernummer|vat|tva|partita\s*iva|p\.?\s*iva|
              btw[\s\-]?nummer|nif|cif|moms|alv|dph|tax\s*(id|number)/xi
  KEYWORD_WINDOW = 60

  MAX_CANDIDATES = 3

  # 返回 [['DE', '129273283'], ...]。排序：挨着税号关键词的最前，
  # 其次是和域名后缀同国的。只给前几个——VIES 有并发限流。
  def self.extract(text, domain: nil)
    body = text.to_s
    found = []
    body.scan(PATTERN) do |cc, rest|
      hit = normalize(cc.upcase, rest)
      found << [hit, near_keyword?(body, Regexp.last_match.begin(0))] if hit
    end
    rank(found.uniq(&:first), domain)
  end

  # 匹配位置往前看一小段里有没有税号关键词。
  def self.near_keyword?(body, offset)
    body[[offset - KEYWORD_WINDOW, 0].max...offset].to_s.match?(KEYWORDS)
  end
  private_class_method :near_keyword?

  def self.rank(found, domain)
    tld = tld_country(domain)
    found.sort_by { |(cc, _), keyworded| [keyworded ? 0 : 1, cc == tld ? 0 : 1] }
         .map(&:first).first(MAX_CANDIDATES)
  end
  private_class_method :rank

  def self.normalize(country, rest)
    body = rest.gsub(SEP_RE, '').upcase
    # 后面可能粘着正文（「DE129273283Geschäftsführer」），按该国长度逐个试着截。
    LENGTHS[country].each do |len|
      candidate = body[0, len]
      return [country, candidate] if candidate.to_s.length == len && FORMATS[country].match?(candidate)
    end
    nil
  end
  private_class_method :normalize

  # 域名后缀猜国家，只用来排序候选。欧盟税号的国家码和域名后缀不一定一致
  # （德国公司用 .com 很常见），所以只影响顺序，不做过滤。
  TLD_TO_COUNTRY = { 'de' => 'DE', 'at' => 'AT', 'fr' => 'FR', 'it' => 'IT', 'es' => 'ES',
                     'nl' => 'NL', 'be' => 'BE', 'se' => 'SE', 'dk' => 'DK', 'fi' => 'FI',
                     'pl' => 'PL', 'pt' => 'PT', 'cz' => 'CZ', 'ie' => 'IE', 'gr' => 'EL',
                     'hu' => 'HU', 'ro' => 'RO', 'sk' => 'SK', 'si' => 'SI', 'lu' => 'LU' }.freeze

  def self.tld_country(domain)
    TLD_TO_COUNTRY[domain.to_s.split('.').last.to_s.downcase]
  end
  private_class_method :tld_country
end
