# 从**已经抓下来的**官网正文里提联系方式。不额外发一个请求——
# 背调本来就把首页、法律信息页、关于我们、联系方式页都抓过了（Crm::CompanySiteFetcher），
# 其中法律信息页在欧盟是法律强制页，必须列出邮箱。
#
# 为什么要这个（2026-11-10）：Apollo 解锁一个邮箱扣一个 credit，一个计费周期烧掉 2157 个
# 而业务员实际用上 2 个。官网上的业务邮箱是公开信息，一分钱不花。
#
# ⚠️ 它是**补充不是替代**：实测 50 分以上的公司命中率 45%（9/20），提到的是 sales@ /
# contact@ 这类公共信箱，回信率低于解锁出来的个人邮箱。价值在额度断档时有东西可发，
# 以及给那些不值得花 credits 的低分公司兜底。
class Crm::SiteContactFinder
  Result = Struct.new(:emails, :contact_url, keyword_init: true)

  MAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/
  # 图片文件名、第三方 SDK、示例地址——正则扫正文必然会扫出这些。
  JUNK = /\.(png|jpe?g|gif|webp|svg|ico)$|@2x|sentry|wixpress|example\.(com|org)|
          godaddy|sentry\.io|\.wixsite|yourdomain|domain\.com/xi
  # 业务口优先：发开发信要进销售的信箱，不是 hr@ / jobs@ / privacy@。
  BIZ = /\A(sales|info|contact|kontakt|vertrieb|office|hello|enquir|inquir|
             export|purchas|einkauf|commercial|devis|mail|ventas|commerciale)/xi
  # 这些前缀永远不要：发过去没人看，还可能被当成骚扰投诉。
  NEVER = /\A(privacy|datenschutz|dpo|legal|recht|abuse|postmaster|webmaster|
               noreply|no-reply|bounce|jobs|karriere|career|hr|bewerbung|press|presse)/xi
  MAX_EMAILS = 3

  def self.call(site, domain: nil)
    new(site, domain).call
  end

  def initialize(site, domain)
    @site = site || {}
    @domain = domain.to_s.presence || host_of(@site[:url])
  end

  def call
    Result.new(emails: pick_emails, contact_url: contact_page_url)
  end

  private

  # 法律信息页那份是**没截断的原文**（见 CompanySiteFetcher），邮箱常排在页尾，
  # 所以必须和正文拼起来一起扫，只扫 text 会把它切掉。
  def text = @text ||= [@site[:legal_text], @site[:text]].compact.join("\n")

  def pick_emails
    text.scan(MAIL).map(&:downcase).uniq.reject { |m| junk?(m) }
        .sort_by { |m| rank(m) }.first(MAX_EMAILS)
  end

  def junk?(mail)
    mail.match?(JUNK) || local(mail).match?(NEVER) || mail.length > 60
  end

  # 自己域名的排前面，业务口的再排前面——两条都不满足的留着当兜底。
  def rank(mail)
    [own_domain?(mail) ? 0 : 1, local(mail).match?(BIZ) ? 0 : 1, mail]
  end

  def local(mail) = mail.split('@').first.to_s

  def host_of(url)
    URI.parse(url.to_s).host.to_s
  rescue URI::InvalidURIError
    ''
  end

  # 自己域名下的邮箱优先：扫正文难免扫到合作伙伴、建站公司的地址。
  def own_domain?(mail)
    root = @domain.split('.').first.to_s.downcase
    root.present? && mail.split('@').last.to_s.include?(root)
  end

  # 子页在正文里是「【联系方式】https://...」这个格式（见 CompanySiteFetcher#sub_page_blocks）。
  # 提不到邮箱时这条链接就是业务员唯一的入口——比给他一片空白强。
  def contact_page_url
    text[%r{【联系方式】(https?://\S+)}, 1] || text[%r{【法律信息页】(https?://\S+)}, 1]
  end
end
