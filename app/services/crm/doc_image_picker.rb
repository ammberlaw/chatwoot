# 从公司文档里挑图：产品图基本都放在「设计资料」板块，核价表挑现成的比重新上传省事。
# 可见范围与文档模块一致：公司文档 + 本人的个人文档。
class Crm::DocImagePicker
  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp image/bmp].freeze
  LIMIT = 200

  def initialize(account:, user:, section_id: nil, query: nil)
    @account = account
    @user = user
    @section_id = section_id.presence
    @query = query.presence
  end

  # 有图可挑的资料板块（设计资料排最前，那儿放的就是产品图）。
  def sections
    ids = ActiveStorage::Attachment.where(record_type: 'Crm::KnowledgeDoc', name: 'files')
                                   .joins(:blob).where(active_storage_blobs: { content_type: IMAGE_TYPES })
                                   .joins('INNER JOIN crm_knowledge_docs d ON d.id = active_storage_attachments.record_id')
                                   .where(d: { account_id: @account.id })
                                   .distinct.pluck(Arel.sql('d.section_id')).compact
    @account.crm_doc_sections.where(id: ids)
            .sort_by { |s| s.name.include?('设计') ? 0 : 1 }
            .map { |s| { id: s.id, name: s.name } }
  end

  def images
    attachments.limit(LIMIT).map { |att| row(att) }
  end

  def attachment(id)
    attachments.find_by(id: id)
  end

  private

  def attachments
    scope = image_attachments(pickable_docs)
    # 设计资料板块文档很多，光按文档名搜不够，图片文件名也一起匹配。
    scope = scope.or(image_attachments(section_docs).where('active_storage_blobs.filename ILIKE :q', q: "%#{@query}%")) if @query
    # record 是多态关联，只能 preload 不能 includes（includes 会试图 eager_load 而报错）
    scope.preload(:blob, :record).order(id: :desc)
  end

  def image_attachments(docs)
    ActiveStorage::Attachment.where(record_type: 'Crm::KnowledgeDoc', record_id: docs.select(:id), name: 'files')
                             .joins(:blob).where(active_storage_blobs: { content_type: IMAGE_TYPES })
  end

  def pickable_docs
    return section_docs if @query.blank?

    section_docs.where('crm_knowledge_docs.name ILIKE :q', q: "%#{@query}%")
  end

  # 按板块收口的可见文档（不带关键词），也作为「按文件名搜」的范围。
  def section_docs
    docs = @account.crm_knowledge_docs.kept
    docs = docs.company_docs.or(docs.personal_of(@user.id))
    @section_id ? docs.where(section_id: @section_id) : docs
  end

  def row(att)
    { id: att.id, filename: att.blob.filename.to_s, doc_name: att.record&.name,
      byte_size: att.blob.byte_size,
      url: Rails.application.routes.url_helpers.rails_blob_path(att.blob, only_path: true) }
  end
end
