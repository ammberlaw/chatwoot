class Crm::KnowledgeImageLibrary
  include Rails.application.routes.url_helpers

  def initialize(docs:, account:, params:)
    @docs = docs
    @account = account
    @params = params
    @images = ActiveStorage::Attachment.where(record_type: 'Crm::KnowledgeDoc', record_id: docs.select(:id))
                                       .joins(:blob).where("active_storage_blobs.content_type LIKE 'image/%'")
  end

  def perform
    image_docs = @account.crm_knowledge_docs.where(id: @images.select(:record_id))
    sections = @account.crm_doc_sections.where(id: image_docs.select(:section_id)).order(:name).pluck(:name)
    if @params[:image_section].present?
      image_docs = image_docs.where(section_id: @account.crm_doc_sections.where(name: @params[:image_section]).select(:id))
    end
    categories = image_docs.where.not(category: nil).distinct.pluck(:category).sort
    image_docs = image_docs.where(category: @params[:image_category]) if @params[:image_category].present?
    images = @images.where(record_id: image_docs.select(:id))
    page = [@params[:page].to_i, 1].max
    size = @params[:per_page].present? ? @params[:per_page].to_i.clamp(1, 100) : 48
    count = images.count
    { payload: rows(images.order(:record_id, :id).offset((page - 1) * size).limit(size)), count: count,
      categories: categories, sections: sections, page: page, has_more: page * size < count }
  end

  private

  def rows(images)
    attachments = images.includes(:blob).to_a
    docs_by_id = @docs.where(id: attachments.map(&:record_id)).includes(:section).index_by(&:id)
    attachments.map do |file|
      doc = docs_by_id.fetch(file.record_id)
      { doc_id: doc.id, attachment_id: file.id, blob_id: file.blob.id, signed_id: file.signed_id,
        name: doc.name, category: doc.category, section_name: doc.section&.name, byte_size: file.blob.byte_size,
        url: rails_blob_path(file, only_path: true) }
    end
  end
end
