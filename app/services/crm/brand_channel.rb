# 认出「品牌授权渠道」：OPPO 意大利独家总代、三星品牌专卖店、小米授权经销商这一类。
#
# 为什么要专门挡：它们各项信号看着都像好客户——营收上亿、有零售渠道、正好做平板和手机，
# 初筛给了 85 分。但它们卖的是**品牌方的货**，货源、包装、系统全由品牌方定，
# 不可能回头找工厂定制自己的牌子。我们做的是 ODM 定制，这类公司永远不会是买家。
#
# 用规则不用模型：模型看「OPPO 独家经销商」容易被「经销商」三个字带到 yes，
# 而这件事的判据是死的——名字里既有品牌又有授权字样，就是品牌渠道。
class Crm::BrandChannel
  # 手机/消费电子品牌。只放**会自建授权渠道**的那些。
  # ⚠️ 别加两三个字母的缩写（HP、LG）：误伤一大片正常公司名。
  BRANDS = %w[
    oppo xiaomi samsung huawei apple vivo realme honor oneplus redmi
    lenovo motorola nokia alcatel tcl hisense sony asus acer
    google amazon microsoft nothing poco infinix tecno itel
  ].freeze

  # 够独特、可以靠「名字以它开头」就认定是品牌分公司的那些。
  # ⚠️ apple / honor / vivo / nothing / poco / tecno 一律不放进来——
  # 它们都是常用词或常见词根（Apple Valley Foods、Vivobarefoot），会误伤。
  SUBSIDIARY_BRANDS = %w[
    samsung xiaomi huawei oppo lenovo motorola nokia alcatel hisense oneplus redmi infinix
  ].freeze
  SUBSIDIARY = /\A\s*(?:#{SUBSIDIARY_BRANDS.join('|')})(?![a-z])/i

  # 授权字样。各语种都要——意大利的写 autorizzato，西班牙的写 autorizado。
  CHANNEL_WORDS = [
    'authorized', 'authorised', 'autorizado', 'autorizzato', 'autorisé', 'autorisierter',
    'exclusive distributor', 'distributore esclusivo', 'distribuidor exclusivo',
    'official store', 'official reseller', 'brand store', 'flagship store',
    'concesionario', 'revendeur agree', 'vertragshändler', 'premium partner',
    '专卖', '授权'
  ].freeze

  # 品牌自营商城的域名：oppostore.it、samsung-shop.de 这种。
  STORE_DOMAIN = /\A(?:www\.)?(#{BRANDS.join('|')})[-_]?(?:store|shop|mobile|online)\./i
  # 名字里「品牌 + 门店」连着写：Samsung Store Milano、Huawei Experience Store。
  # 这种不带「授权」二字，但同样是品牌自己的店。
  BRAND_STORE = /
    (?<![a-z])(#{BRANDS.join('|')})(?![a-z])\s*
    (?:experience\s*)?(?:store|shop|center|centre|point|space|tienda|negozio|boutique)(?![a-z])
  /xi

  class << self
    # 三种都算品牌渠道：品牌自营商城的域名、品牌自己的分公司、名字带授权字样的经销商。
    def brand_channel?(name:, domain: nil)
      return true if domain.present? && domain.to_s.match?(STORE_DOMAIN)

      text = name.to_s.downcase
      return false if text.blank?

      subsidiary?(text) || store?(text) || authorized?(text)
    end

    private

    # 「Samsung Germany」「Huawei Technologies Italia」——品牌自己的分公司，
    # 定义上就不可能是买家。名字以品牌开头就是它。
    def subsidiary?(text) = text.match?(SUBSIDIARY)

    def store?(text) = text.match?(BRAND_STORE)

    def authorized?(text)
      brand_in?(text) && CHANNEL_WORDS.any? { |word| text.include?(word) }
    end

    # 整词匹配：别让 "Honorlux"（卤味店）撞上 honor。
    def brand_in?(text)
      BRANDS.any? { |brand| text.match?(/(?<![a-z])#{Regexp.escape(brand)}(?![a-z])/) }
    end
  end
end
