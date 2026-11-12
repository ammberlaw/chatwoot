class Crm::EmployeeFiles
  KINDS = { 'photo' => :photo, 'entry' => :entry_files, 'resign' => :resign_files }.freeze

  def initialize(employee:, actor:)
    @employee, @actor = employee, actor
  end

  def attach(kind, uploads, key: nil)
    kind = kind.to_s
    raise Crm::OffboardingService::Invalid, '附件类别不正确' unless KINDS.key?(kind)
    files = Array(uploads)
    unless files.any? && files.all? { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }
      raise Crm::OffboardingService::Invalid, '请选择有效文件'
    end
    raise Crm::OffboardingService::Invalid, '证件照一次只能上传一张' if kind == 'photo' && files.size != 1
    raise Crm::OffboardingService::Invalid, '上传标识不正确' if key && (!key.is_a?(String) || key.length > 128)

    fingerprint = Digest::SHA256.hexdigest(JSON.generate([kind, files.map { |file| [file.original_filename, file.size, Digest::MD5.file(file.tempfile.path).base64digest] }]))
    staged = []
    files.each do |file|
      file.tempfile.rewind
      staged << ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename, content_type: file.content_type)
    end
    @employee.account.with_lock(requires_new: true) do
      @employee.lock!
      previous = Crm::HrEvent.where(employee: @employee, kind: 'files_uploaded').where("payload ->> 'upload_key' = ?", key).first if key.present?
      if previous
        raise Crm::OffboardingService::Invalid, '上传标识已使用，请重新选择文件' unless previous.payload['fingerprint'] == fingerprint
      else
        association = @employee.public_send(KINDS.fetch(kind))
        archive_replaced_photo(association) if kind == 'photo' && association.attached?
        association = @employee.public_send(KINDS.fetch(kind))
        association.attach(kind == 'photo' ? staged.first : staged)
        Crm::HrEvent.record!(account: @employee.account, employee: @employee, actor: @actor, kind: 'files_uploaded',
                            payload: { file_kind: kind, filenames: staged.map { |blob| blob.filename.to_s }, upload_key: key, fingerprint: fingerprint })
      end
    end
  ensure
    Array(staged).each do |blob|
      next if blob.attachments.exists?
      begin
        blob.purge
      rescue StandardError => error
        Rails.logger.warn("[HR附件] unused upload cleanup: #{error.class}")
      end
    end
  end

  def remove(attachment_id)
    @employee.account.with_lock(requires_new: true) do
      @employee.lock!
      file = ActiveStorage::Attachment.where(record: @employee, name: KINDS.values).find(attachment_id)
      kind = KINDS.key(file.name.to_sym)
      Crm::HrEvent.record!(account: @employee.account, employee: @employee, actor: @actor, kind: 'files_removed',
                          payload: { file_kind: kind, filenames: [file.filename.to_s] }, files: [file.blob])
      file.destroy!
    end
  end

  def restore(event_id)
    @employee.account.with_lock(requires_new: true) do
      @employee.lock!
      event = Crm::HrEvent.where(employee: @employee, kind: %w[files_removed photo_replaced]).find(event_id)
      association = @employee.public_send(KINDS.fetch(event.payload.fetch('file_kind')))
      archive_replaced_photo(association) if event.payload['file_kind'] == 'photo' && association.attached?
      association = @employee.public_send(KINDS.fetch(event.payload.fetch('file_kind')))
      event.files.each do |file|
        next if ActiveStorage::Attachment.exists?(record: @employee, name: KINDS.fetch(event.payload['file_kind']), blob_id: file.blob_id)
        association.attach(file.blob)
      end
      Crm::HrEvent.record!(account: @employee.account, employee: @employee, actor: @actor, kind: 'files_restored',
                          payload: { source_event_id: event.id, file_kind: event.payload['file_kind'], filenames: event.files.map { |file| file.filename.to_s } })
    end
  end

  private

  def archive_replaced_photo(association)
    Crm::HrEvent.record!(account: @employee.account, employee: @employee, actor: @actor, kind: 'photo_replaced',
                        payload: { file_kind: 'photo', filenames: [association.filename.to_s] }, files: [association.blob])
    association.attachment.destroy!
    @employee.reload
  end
end
