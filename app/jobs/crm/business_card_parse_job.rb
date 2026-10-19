# 名片识别放后台：展会现场连拍，传完就该能拍下一张，不能卡着等 OCR 和模型。
class Crm::BusinessCardParseJob < ApplicationJob
  queue_as :low

  # 识别失败已经在 Parser 里落成 parse_error 了，这里不用重试——
  # 重试只会把同一张图再送一遍 OCR 白花钱，人在校对页手工填更快。
  def perform(card_id)
    card = Crm::BusinessCard.find_by(id: card_id)
    return if card.blank? || card.status != 'PENDING'

    Crm::BusinessCardParser.call(card)
  end
end
