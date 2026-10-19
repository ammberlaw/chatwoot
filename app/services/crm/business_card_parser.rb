# 名片识别：照片 → 视觉模型读成结构化字段 → 落回名片记录。
# 由 Crm::BusinessCardParseJob 在后台调用——展会现场连拍时不能让人等识别，
# 传完就该能拍下一张。
class Crm::BusinessCardParser
  def self.call(card)
    new(card).call
  end

  def initialize(card)
    @card = card
  end

  def call
    raise Crm::VisionCardReader::Error, '名片照片丢失' unless @card.image.attached?

    data = Crm::VisionCardReader.new(account: @card.account)
                                .read(@card.image.download, @card.image.content_type)
    @card.update!(attributes_from(data).merge(status: 'PARSED', parsed_at: Time.current, parse_error: nil))
    @card
  rescue StandardError => e
    Rails.logger.warn("[Crm::BusinessCardParser] card=#{@card.id} #{e.class}: #{e.message}")
    # 仍然置为 PARSED：识别不出来不代表这张名片没用，照片还在，人能照着照片手工填。
    # 卡在 PENDING 的话列表上看着像还在跑，永远等不到。
    @card.update!(status: 'PARSED', parsed_at: Time.current, parse_error: e.message.to_s.truncate(300))
    @card
  end

  private

  # 模型给的字段逐个洗一遍再落库：它偶尔会把「null」当字符串给回来。
  def attributes_from(data)
    attrs = Crm::BusinessCard::EDITABLE_FIELDS.each_with_object({}) do |field, h|
      next if %w[event_name remark].include?(field) # 这两个是人填的，模型不碰

      value = field == 'country' ? clean_country(data[field]) : clean(data[field])
      h[field] = value if value.present?
    end
    # 原文留着给校对的人跟照片对照，所以不截断到 255。
    attrs.merge(raw_text: data['raw_text'].to_s.strip.presence)
  end

  def clean(value)
    s = value.to_s.strip
    return nil if s.blank? || %w[null none n/a 无].include?(s.downcase)

    s.truncate(255)
  end

  # 国家必须落在客户表的白名单里：trade_country 带 inclusion 校验，
  # 模型万一给了列表外的写法，这里不拦就要等到建客户那一刻才炸（而且是 500）。
  def clean_country(value)
    code = clean(value)&.upcase
    Crm::Customer::COUNTRIES.include?(code) ? code : nil
  end
end
