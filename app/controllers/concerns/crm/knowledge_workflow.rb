module Crm::KnowledgeWorkflow
  extend ActiveSupport::Concern

  included do
    before_action(only: [:versions, :restore_version, :replace_file, :retry_extraction, :preference, :opened, :maintainers]) { fetch_doc }
    before_action(only: [:restore_version, :replace_file, :retry_extraction, :maintainers]) { ensure_doc_manageable }
  end

  def uploaders
    ids = section_scoped(visible_docs).where.not(created_by_id: nil).select(:created_by_id)
    rows = User.where(id: ids).order(:id).map { |user| { id: user.id, name: user.crm_display_name } }
    render json: { payload: rows }
  end

  def maintainers
    rows = Current.account.users.order(:id).map { |user| { id: user.id, name: user.crm_display_name } }
    render json: { payload: rows }
  end

  def versions
    rows = @doc.versions.order(number: :desc).includes(:user, files_attachments: :blob).map do |version|
      { id: version.id, number: version.number, note: version.note, name: version.name, summary: version.summary,
        body: version.body, user_name: version.user&.crm_display_name, created_at: version.created_at,
        files: version.files.map { |file| { id: file.id, filename: file.filename.to_s, url: rails_blob_path(file, only_path: true) } } }
    end
    render json: { payload: rows }
  end

  def restore_version
    version = @doc.versions.find(params[:version_id])
    @doc.revise!(user: current_user, note: "恢复版本 V#{version.number}") do
      @doc.update!(name: version.name, summary: version.summary, body: version.body, files: version.files.blobs.to_a)
      @doc.invalidate_extraction!
    end
    render_changed_document
  end

  def replace_file
    raise ActionController::BadRequest, '请选择新文件' unless params[:file].is_a?(ActionDispatch::Http::UploadedFile)

    @doc.revise!(user: current_user, note: params[:note].presence || '替换附件') do
      attachment = @doc.files.find(params[:attachment_id])
      attachment.destroy!
      @doc.files.attach(params[:file])
      @doc.invalidate_extraction!
    end
    render_changed_document
  end

  def retry_extraction
    @doc.with_lock { @doc.invalidate_extraction! }
    render_changed_document
  end

  def preference
    row = @doc.preferences.create_or_find_by!(user_id: current_user.id)
    row.update!(favorite: ActiveModel::Type::Boolean.new.cast(params.require(:favorite)))
    render json: { favorite: row.favorite }
  end

  def opened
    row = @doc.preferences.create_or_find_by!(user_id: current_user.id)
    row.update!(last_opened_at: Time.current)
    head :ok
  end

  def bulk
    result = Crm::KnowledgeBatch.new(account: Current.account, user: current_user, docs: section_scoped(visible_docs),
                                     categories: downloadable_categories, params: params,
                                     manageable: method(:doc_manageable?), folder_manageable: method(:folder_manageable?)).perform
    result[:copies].each { |doc| extract_text_later(doc) }
    render json: { count: result[:count] }
  end

  private

  def folder_manageable?(folder)
    return folder.user_id == current_user.id if folder.user_id

    company_docs_creatable?(folder.section_id == sales_section_id ? 'SALES' : 'GENERAL', folder.section_id)
  end

  def render_changed_document
    extract_text_later(@doc)
    prepare_doc_metadata([@doc])
    render 'api/v1/accounts/crm/knowledge_docs/show'
  end

  def prepare_doc_metadata(docs)
    ids = docs.map(&:id)
    @doc_preferences = Crm::KnowledgePreference.where(doc_id: ids, user_id: current_user.id).index_by(&:doc_id)
    @doc_versions = Crm::KnowledgeVersion.where(doc_id: ids).group(:doc_id).maximum(:number)
    folders = downloadable_categories.index_by(&:id)
    @folder_paths = folders.transform_values do |folder|
      parts = []
      seen = Set.new
      while folder && seen.add?(folder.id)
        parts.unshift(folder.name)
        folder = folders[folder.parent_id]
      end
      parts.join(' / ')
    end
  end
end
