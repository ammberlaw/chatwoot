# 收信后自动归档：把客户来信里的真实附件（PI/合同/规格书等，排除内联签名图）挂到该客户档案，
# 并用 AI 判定单证类型打标签，业务员不用手动存、客户资料自动齐全（对标小满「关键附件自动归档」）。
# 只处理已关联客户的来信；幂等：同一 blob 已挂到该客户则跳过；失败只记日志不影响收信。
class Crm::ArchiveEmailAttachmentsJob < ApplicationJob
  queue_as :low

  def perform(email_id)
    email = Crm::Email.find_by(id: email_id)
    return if email.nil? || email.crm_customer_id.blank?

    customer = Crm::Customer.find_by(id: email.crm_customer_id)
    return if customer.nil?

    # 内联图（签名 logo / 正文嵌图）不归档，只收真实附件。
    blobs = email.files.blobs.reject { |b| b.metadata['inline'] }
    return if blobs.empty?

    types = Crm::EmailAiService.new(account: email.account)
                               .classify_attachments(subject: email.subject.to_s, filenames: blobs.map { |b| b.filename.to_s })

    # 幂等键：该客户下已归档过的 (邮件id, 文件名)。复制而非共享 blob——否则删邮件会连带 purge 掉客户已归档的副本。
    archived = customer.files.blobs.filter_map do |b|
      [b.metadata['crm_email_id'], b.filename.to_s] if b.metadata['crm_source'] == 'email'
    end.to_set

    blobs.each do |blob|
      next if archived.include?([email.id, blob.filename.to_s])

      copy = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(blob.download),
        filename: blob.filename,
        content_type: blob.content_type,
        metadata: {
          'crm_doc_type' => types[blob.filename.to_s].presence || 'OTHER',
          'crm_source' => 'email',
          'crm_email_id' => email.id,
          'crm_email_subject' => email.subject.to_s,
          'crm_email_date' => email.email_date&.iso8601
        }
      )
      customer.files.attach(copy)
    end
  rescue StandardError => e
    Rails.logger.warn("[Crm::ArchiveEmailAttachmentsJob] email=#{email_id} #{e.class}: #{e.message}")
  end
end
