# 把知识库文档的附件抽成可搜索正文，存进 extracted_text。
#
# AI 答产品问题全靠它：生产库 1452 篇文档里正文超 50 字的只有 2 篇，其余是挂着 PDF
# 的空壳，所以客户问「K705 过了哪些认证」，助手只查得到有这么一份报告、读不出内容。
#
# 不调模型，纯解析，所以可以对全库跑一遍而不心疼钱。
class Crm::KnowledgeExtractJob < ApplicationJob
  # 和收信、初筛同一档：补录慢一点没关系，绝不能挤掉发信。
  queue_as :low

  # 一篇文档可能挂好几个附件（规格书 + 认证报告），逐个抽、拼起来。
  # 上限防的是有人把整本画册传上来——几十万字塞进一行，搜索和喂给模型都受不了。
  # 取模型上的常量：这里截断、那边校验，两个数一旦不一致，抽出来的文档就再也保存不了
  # （2026-11-06 的 422 就是这么来的）。
  MAX_CHARS = Crm::KnowledgeDoc::EXTRACTED_TEXT_MAX
  # 少于这个字数当没抽到：PDF 里零星几个字符多半是页眉页脚，不是正文。
  MIN_USEFUL = 30

  def perform(doc_id, revision = nil)
    doc = Crm::KnowledgeDoc.kept.find_by(id: doc_id)
    return if doc.nil?

    revision ||= doc.extract_revision
    return unless revision == doc.extract_revision

    texts, errors, skipped = collect(doc)
    doc.with_lock { apply(doc, texts, errors, skipped) if doc.discarded_at.nil? && doc.extract_revision == revision }
  rescue StandardError => e
    Rails.logger.error("[kb extract] doc=#{doc_id} 失败：#{e.class} #{e.message}")
    doc&.with_lock do
      if doc.extract_revision == revision && doc.discarded_at.nil?
        doc.update_columns(extract_state: 'failed', extract_error: "#{e.class}: #{e.message}".truncate(200), extracted_at: Time.current)
      end
    end
  end

  private

  def collect(doc)
    texts = []
    errors = []
    skipped = 0
    doc.files.each do |att|
      blob = att.blob
      # 视频和图片直接跳过：生产知识库里 728 个 mp4、727 张图，起任务去解析它们纯属浪费。
      # （图片真要读得走视觉模型，那是另一条路、要花钱，不在这个任务里做。）
      next (skipped += 1) unless Crm::DocumentText.extractable?(blob.filename.to_s, blob.content_type.to_s)

      texts << one_file(blob, errors)
    end
    [texts.compact.reject(&:blank?), errors, skipped]
  end

  def one_file(blob, errors)
    extractor = Crm::DocumentText.from_blob(blob)
    text = extractor.call.to_s.strip
    return nil if text.length < MIN_USEFUL

    "【#{blob.filename}】\n#{text}"
  rescue Crm::DocumentText::UnsupportedType => e
    errors << "#{blob.filename}: #{e.message}"
    nil
  rescue StandardError => e
    Rails.logger.warn("[kb extract] blob=#{blob.id} #{e.class}: #{e.message}")
    errors << "#{blob.filename}: #{e.class}"
    nil
  end

  # 状态要分清楚，否则补录任务会对「确实没有文字层」的那几份永远重试：
  #   done    抽到正文
  #   empty   有可解析的附件，但抽出来是空的（已转曲的画册、扫描件）
  #   skipped 压根没有可解析的附件（纯视频/图片文档）
  #   failed  解析报错
  def apply(doc, texts, errors, skipped)
    state = if texts.any? then 'done'
            elsif errors.any? then 'failed'
            elsif skipped.positive? then 'skipped'
            else
              'empty'
            end
    doc.update_columns( # rubocop:disable Rails/SkipsModelValidations
      extracted_text: texts.join("\n\n").truncate(MAX_CHARS).presence,
      extracted_at: Time.current,
      extract_state: state,
      extract_error: errors.first(3).join('；').presence
    )
  end
end
