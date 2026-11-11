# Restoring a folder restores only documents removed with that folder, not older individually deleted files.
class Crm::KnowledgeTrash
  def self.restore_document!(doc, user_id)
    doc.account.with_lock do
      restore_ancestors!(doc.folder)
      doc.restore!(user_id)
    end
  end

  def self.restore_folder!(folder, user_id)
    folder.account.with_lock do
      batch = folder.trash_batch
      folders = folder.account.crm_knowledge_categories.index_by(&:id)
      ids = Set.new([folder.id])
      loop do
        extra = folders.values.select { |child| ids.include?(child.parent_id) }.map(&:id) - ids.to_a
        break if extra.empty?

        ids.merge(extra)
      end
      restore_ancestors!(folder)
      folders.values.select { |child| ids.include?(child.id) && child.discarded_at && child.trash_batch == batch }.each do |child|
        restore_one!(child)
      end
      folder.account.crm_knowledge_docs.discarded.where(category_id: ids.to_a, trash_batch: batch).find_each { |doc| doc.restore!(user_id) }
    end
  end

  def self.restore_one!(folder)
    scope = folder.account.crm_knowledge_categories.kept.where(user_id: folder.user_id, section_id: folder.section_id, parent_id: folder.parent_id)
    name = folder.name
    index = 1
    while scope.where.not(id: folder.id).exists?(name: name)
      index += 1
      name = "#{folder.name} (#{index})"
    end
    folder.update!(name: name, discarded_at: nil, discarded_by_id: nil, trash_batch: nil)
    folder.account.crm_knowledge_docs.where(category_id: folder.id).update_all(category: name) # rubocop:disable Rails/SkipsModelValidations
  end

  def self.restore_ancestors!(folder)
    seen = Set.new
    while folder && seen.add?(folder.id)
      restore_one!(folder) if folder.discarded_at
      folder = folder.parent
    end
  end
end
