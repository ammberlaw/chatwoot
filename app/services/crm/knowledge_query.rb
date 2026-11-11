# All filters refine an already authorized relation; none can broaden its visibility.
class Crm::KnowledgeQuery
  def initialize(docs:, user_id:, params:)
    @docs = docs
    @user_id = user_id
    @params = params
  end

  def resolve
    scope = @docs
    scope = scope.company_docs if @params[:filter] == 'company'
    scope = scope.personal_of(@user_id) if @params[:filter] == 'mine'
    scope = preferences(scope) if %w[favorites recent].include?(@params[:filter])
    scope = scope.where(created_by_id: @params[:uploader_id]) if @params[:uploader_id].present?
    scope = updated_since(scope) if @params[:updated_after].present?
    scope = file_type(scope) if @params[:file_type].present?
    scope = scope.where(category: @params[:category]) if @params[:category].present?
    @params[:q].present? ? search(scope) : scope
  end

  private

  def preferences(scope)
    scope = scope.joins(:preferences).where(crm_knowledge_preferences: { user_id: @user_id })
    return scope.where(crm_knowledge_preferences: { favorite: true }) if @params[:filter] == 'favorites'

    scope.where.not(crm_knowledge_preferences: { last_opened_at: nil })
  end

  def updated_since(scope)
    day = Date.iso8601(@params[:updated_after])
    scope.where('crm_knowledge_docs.updated_at >= ?', day.beginning_of_day)
  rescue ArgumentError
    raise ActionController::BadRequest, '无效日期'
  end

  def file_type(scope)
    types = { 'image' => 'image/%', 'video' => 'video/%', 'pdf' => 'application/pdf', 'office' => 'office' }
    pattern = types.fetch(@params[:file_type]) { raise ActionController::BadRequest, '无效文件类型' }
    files = ActiveStorage::Attachment.where(record_type: 'Crm::KnowledgeDoc').joins(:blob)
    files = if pattern == 'office'
              files.where('active_storage_blobs.filename ~* ?', '\.(docx?|xlsx?|csv|pptx?)$')
            else
              files.where('active_storage_blobs.content_type LIKE ?', pattern)
            end
    scope.where(id: files.select(:record_id))
  end

  def search(scope)
    scope.where(<<~SQL.squish, q: "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q].to_s)}%")
      crm_knowledge_docs.name ILIKE :q OR crm_knowledge_docs.summary ILIKE :q OR crm_knowledge_docs.body ILIKE :q
      OR crm_knowledge_docs.extracted_text ILIKE :q
      OR EXISTS (SELECT 1 FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id = a.blob_id
                 WHERE a.record_type = 'Crm::KnowledgeDoc' AND a.record_id = crm_knowledge_docs.id AND b.filename ILIKE :q)
    SQL
  end
end
