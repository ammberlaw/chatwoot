# 把知识库里选中的文件复制成一份独立的 blob，供邮件/会话当附件发出去。
#
# 为什么复制而不是直接引用原 blob：发出去的东西要锁住当时那一版，知识库原件之后
# 被换了或删了，已经发给客户的那条不该跟着变。
# 为什么在后端复制而不是前端下载再上传：产品目录、报价单动辄几十 MB，走一趟浏览器
# 既慢又白耗业务员的上行带宽。
class Crm::KnowledgeDocSnapshot
  pattr_initialize [:docs!, :file_ids!]

  def perform
    source_attachments.map { |att| copy(att) }
  end

  private

  # 复制源由调用者限定为当前用户可见、未删除的文档。
  def source_attachments
    ids = Array(file_ids).map(&:to_i).uniq
    return ActiveStorage::Attachment.none if ids.empty?

    attachments = ActiveStorage::Attachment.where(
      id: ids, record_type: 'Crm::KnowledgeDoc', record_id: docs.select(:id)
    ).includes(:blob)
    raise ActiveRecord::RecordNotFound unless attachments.size == ids.size

    attachments
  end

  def copy(att)
    blob = att.blob.open do |file|
      ActiveStorage::Blob.create_and_upload!(io: file, filename: att.filename.to_s, content_type: att.blob.content_type)
    end
    { signed_id: blob.signed_id, filename: blob.filename.to_s, content_type: blob.content_type, byte_size: blob.byte_size }
  end
end
