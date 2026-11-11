# Folder and document changes commit together; a hidden or unauthorized source rejects the whole batch.
class Crm::KnowledgeBatch
  def initialize(account:, user:, docs:, categories:, params:, manageable:, folder_manageable:)
    @account = account
    @user = user
    @docs_scope = docs
    @categories_scope = categories
    @params = params
    @manageable = manageable
    @folder_manageable = folder_manageable
    @copies = []
  end

  def perform
    operation = @params.require(:operation)
    raise ActionController::BadRequest, '无效的批量操作' unless %w[move copy discard].include?(operation)

    @account.with_lock do
      @categories = @categories_scope.index_by(&:id)
      prepare_selection!
      authorize_selection!
      case operation
      when 'move' then move
      when 'copy' then copy
      when 'discard' then discard
      end
    end
    { count: @docs.size, copies: @copies }
  end

  private

  def prepare_selection!
    @selected = Array(@params[:category_ids]).map(&:to_i).uniq
    raise ActiveRecord::RecordNotFound unless (@selected - @categories.keys).empty?

    @folder_ids = @selected.to_set
    loop do
      extra = @categories.values.select { |folder| @folder_ids.include?(folder.parent_id) }.map(&:id) - @folder_ids.to_a
      break if extra.empty?

      @folder_ids.merge(extra)
    end
    select_documents!
    @roots = @selected.reject { |id| @folder_ids.include?(@categories.fetch(id).parent_id) }
    raise ActionController::BadRequest, '文件夹存在循环，请先修复目录关系' if @selected.any? && @roots.empty?
  end

  def select_documents!
    ids = Array(@params[:doc_ids]).map(&:to_i).uniq
    raise ActiveRecord::RecordNotFound unless @docs_scope.where(id: ids).count == ids.size

    all = @account.crm_knowledge_docs.kept.where(category_id: @folder_ids.to_a).count
    raise ActiveRecord::RecordNotFound unless @docs_scope.where(category_id: @folder_ids.to_a).count == all

    @docs = @docs_scope.where(id: ids).or(@docs_scope.where(category_id: @folder_ids.to_a)).order(:id).lock.to_a
    raise ActionController::BadRequest, '请选择资料或文件夹' if @docs.empty? && @selected.empty?
  end

  def authorize_selection!
    allowed = @docs.all? { |doc| @manageable.call(doc) } && @folder_ids.all? { |id| @folder_manageable.call(@categories.fetch(id)) }
    raise Pundit::NotAuthorizedError unless allowed

    @target = @params[:target_id].present? ? @categories.fetch(@params[:target_id].to_i) { raise ActiveRecord::RecordNotFound } : nil
    raise ActionController::BadRequest, '不能移动或复制到自身和子文件夹' if @target && @folder_ids.include?(@target.id)
    raise Pundit::NotAuthorizedError if @target && !@folder_manageable.call(@target)
  end

  def discard
    batch = SecureRandom.uuid
    @docs.each do |doc|
      doc.discard!(@user.id)
      doc.update!(trash_batch: batch)
    end
    @folder_ids.each do |id|
      @categories.fetch(id).update!(discarded_at: Time.current, discarded_by_id: @user.id, trash_batch: batch)
    end
  end

  def move
    @roots.each { |id| @categories.fetch(id).update!(parent_id: @target&.id) }
    @docs.reject { |doc| @folder_ids.include?(doc.category_id) }.each do |doc|
      doc.update!(category_id: @target&.id, category: @target&.name, updated_by: @user)
    end
  end

  def copy
    @mapping = {}
    @roots.each { |id| copy_folder_tree(@categories.fetch(id), @target) }
    @docs.each { |doc| @copies << copy_document(doc, @mapping[doc.category_id] || @target) }
  end

  def copy_folder_tree(folder, target)
    attrs = folder.attributes.slice('account_id', 'user_id', 'section_id', 'position')
    duplicate = Crm::KnowledgeCategory.create!(attrs.merge(name: available_folder_name(folder, target), parent: target))
    @mapping[folder.id] = duplicate
    @categories.values.select { |child| child.parent_id == folder.id }.each { |child| copy_folder_tree(child, duplicate) }
  end

  def available_folder_name(folder, target)
    scope = @account.crm_knowledge_categories.where(user_id: folder.user_id, section_id: folder.section_id, parent_id: target&.id)
    name = folder.name
    index = 1
    while scope.exists?(name: name)
      index += 1
      name = "#{folder.name} (#{index})"
    end
    name
  end

  def copy_document(doc, target)
    attrs = doc.attributes.slice('account_id', 'scope', 'library', 'section_id', 'name', 'summary', 'body')
    duplicate = Crm::KnowledgeDoc.create!(attrs.merge(owner: @user, created_by: @user, updated_by: @user,
                                                      category_id: target&.id, category: target&.name))
    duplicate.files.attach(doc.files.blobs.to_a)
    duplicate.record_version!(user: @user, note: '复制文档')
    duplicate.invalidate_extraction!
    duplicate
  end
end
