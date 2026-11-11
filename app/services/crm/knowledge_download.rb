# 按控制器已收口的文档/分类权限组装 ZIP，文件内容通过 ActiveStorage 分块读取。
# ZipKit 负责 ZIP64、CRC 和中文文件名，不落地临时包、不整体读入内存。
class Crm::KnowledgeDownload
  def initialize(docs:, categories:, doc_ids:, category_ids:)
    @docs_scope = docs
    @categories = categories.index_by(&:id)
    @doc_ids = doc_ids.map(&:to_i).uniq
    @category_ids = category_ids.map(&:to_i).uniq
    @paths = Set.new
  end

  def prepare!
    raise ActionController::BadRequest, '请选择要下载的文件或文件夹' if @doc_ids.empty? && @category_ids.empty?
    raise ActiveRecord::RecordNotFound unless (@category_ids - @categories.keys).empty?
    raise ActiveRecord::RecordNotFound unless @docs_scope.where(id: @doc_ids).count == @doc_ids.size

    @folder_ids = descendant_ids
    @docs = @docs_scope.where(id: @doc_ids).or(@docs_scope.where(category_id: @folder_ids))
                       .select(:id, :name, :body, :summary, :category_id).with_attached_files
    self
  end

  def filename
    name = @doc_ids.empty? && @category_ids.one? ? @categories.fetch(@category_ids.first).name : '文档批量下载'
    "#{safe_name(name)}.zip"
  end

  def write(zip)
    @folder_ids.each { |id| add_directory(zip, folder_path(id)) }
    @docs.find_each { |doc| write_document(zip, doc) }
  end

  private

  def write_document(zip, doc)
    directory = folder_path(doc.category_id)
    directory = unique_path(directory + [safe_name(doc.name)]) if doc.files.size > 1
    doc.files.each { |file| write_file(zip, file, directory) }
    write_text(zip, doc, directory) if doc.body.present? || doc.summary.present? || doc.files.empty?
  end

  def write_file(zip, file, directory)
    path = unique_path(directory + [safe_name(file.filename.to_s)])
    blob = file.blob
    zip.write_stored_file(path.join('/'), modification_time: blob.created_at) do |sink|
      blob.download { |chunk| sink << chunk }
    end
  end

  def descendant_ids
    ids = @category_ids.to_set
    pending = @category_ids.dup
    children = @categories.values.group_by(&:parent_id)
    until pending.empty?
      Array(children[pending.shift]).each do |child|
        pending << child.id if ids.add?(child.id)
      end
    end
    ids.to_a
  end

  def folder_path(id)
    parts = []
    seen = Set.new
    while (category = @categories[id]) && seen.add?(id)
      name = safe_name(category.name)
      # 聚合视图中，不同板块可能有同名顶层目录；仅在同名时附 ID 避免合并。
      collisions = @categories.values.count { |other| other.parent_id == category.parent_id && safe_name(other.name) == name }
      parts.unshift(collisions > 1 ? "#{name} (#{category.id})" : name)
      id = category.parent_id
    end
    parts
  end

  def safe_name(name)
    cleaned = name.to_s.gsub(%r{[\x00-\x1f\x7f\\/:*?"<>|]}, '_').strip.sub(/[. ]+\z/, '')
    cleaned.presence || '未命名'
  end

  def unique_path(parts)
    directory = parts[0...-1]
    name = parts.last
    path = parts.join('/')
    index = 1
    until @paths.add?(path)
      index += 1
      extension = File.extname(name)
      stem = File.basename(name, extension)
      path = (directory + ["#{stem} (#{index})#{extension}"]).join('/')
    end
    path.split('/')
  end

  def add_directory(zip, parts)
    path = parts.join('/')
    return unless @paths.add?(path)

    zip.add_empty_directory(dirname: path)
  end

  def write_text(zip, doc, directory)
    path = unique_path(directory + ["#{safe_name(doc.name)}.txt"])
    zip.write_stored_file(path.join('/')) { |sink| sink << [doc.name, doc.summary, doc.body].compact.join("\n\n") }
  end
end
