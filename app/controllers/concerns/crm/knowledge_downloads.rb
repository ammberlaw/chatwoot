module Crm::KnowledgeDownloads
  # 原生表单 POST 带现有登录凭证，由浏览器直接接收 ZIP，不缓存整个压缩包。
  def download
    library = params.require(:library)
    raise ActionController::BadRequest, '无效的资料库' unless Crm::KnowledgeDoc::LIBRARIES.include?(library)

    archive = Crm::KnowledgeDownload.new(
      docs: filtered_docs, categories: downloadable_categories,
      doc_ids: params[:doc_ids].to_s.split(','), category_ids: params[:category_ids].to_s.split(',')
    )
    archive.prepare!
    zip_kit_stream(filename: archive.filename) { |zip| archive.write(zip) }
  end

  private

  def downloadable_categories
    scope = Current.account.crm_knowledge_categories.kept
    scope = case params[:filter]
            when 'mine' then scope.personal_of(current_user.id)
            when 'company' then scope.company_scope
            else scope.where(user_id: [nil, current_user.id])
            end
    scope = download_category_library(scope)
    scope = scope.where(section_id: params[:section_id]) if params[:section_id].present?
    scope
  end

  def download_category_library(scope)
    if params[:library] == 'GENERAL' && !admin_like?
      scope.where(section_id: [nil] + visible_section_ids + managed_section_ids)
    elsif params[:library] == 'SALES'
      scope.where(section_id: sales_section_id).or(scope.personal_of(current_user.id))
    else
      scope
    end
  end
end
