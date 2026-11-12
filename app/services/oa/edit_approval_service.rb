class Oa::EditApprovalService
  def initialize(request:, actor:, attributes:, submit: false)
    @request = request
    @actor = actor
    @attributes = attributes
    @submit = submit
  end

  def perform
    notify = false
    @request.account.account_users.active_members.find_by!(user_id: @actor.id).with_lock do
      @request.template.with_lock do
        @request.with_lock do
          raise Oa::FormValidator::InvalidForm, '只能修改自己发起的申请' unless @request.applicant_id == @actor.id
          next if @submit && @request.status != 'draft' && @request.events.exists?(kind: 'draft_saved')

          draft = @request.status == 'draft'
          raise Oa::FormValidator::InvalidForm, '申请已审批或已转交，请撤回后修改重提' unless @request.editable_by?(@actor.id)

          template = @request.template
          if draft
            raise Oa::FormValidator::InvalidForm, '模板已停用，无法提交' if @submit && !template.active?
            if @attributes[:template_revision].present? && template.revision != @attributes[:template_revision].to_i
              raise Oa::FormValidator::InvalidForm, '模板已更新，请重新打开并核对表单'
            end

            @request.template_snapshot = template.snapshot
          else
            @request.freeze_definition!
          end
          data = @attributes[:form_data] || @request.form_data
          department_id = @attributes.key?(:department_id) ? @attributes[:department_id].presence : @request.department_id
          Oa::FormValidator.new(account: @request.account, applicant: @actor, definition: @request.definition, form_data: data,
                                department_id: department_id, partial: draft && !@submit).validate!
          validate_rules!(data) unless draft && !@submit
          before = @request.attributes.slice('form_data', 'department_id', 'title')
          before['department_name'] = @request.account.org_departments.find_by(id: @request.department_id)&.name
          removed = @request.files.where(id: Array(@attributes[:remove_file_ids]).map(&:to_i)).to_a
          raise ActiveRecord::RecordNotFound if removed.size != Array(@attributes[:remove_file_ids]).map(&:to_i).uniq.size

          @request.update!(title: @attributes[:title].presence || @request.title, department_id: department_id, form_data: data,
                           department_name_snapshot: @request.account.org_departments.find_by(id: department_id)&.name)
          after = @request.attributes.slice('form_data', 'department_id', 'title')
          after['department_name'] = @request.account.org_departments.find_by(id: @request.department_id)&.name
          payload = { 'before' => before, 'after' => after,
                      'removed_files' => removed.map { |file| file.filename.to_s } }
          event = @request.event!(draft && !@submit ? 'draft_saved' : 'edited', actor: @actor, payload: payload, files: removed.map(&:blob))
          removed.each(&:destroy!)
          @request.files.attach(@attributes[:files]) if @attributes[:files].present?
          event.update!(payload: event.payload.merge('files' => @request.files.map { |file| file.filename.to_s }))
          if !draft || @submit
            @request.update!(status: 'pending', submitted_at: draft ? Time.current : @request.submitted_at,
                             cc_user_ids: Array(@request.definition.cc_user_ids).map(&:to_i).uniq)
            Oa::SubmitApprovalService.rebuild_steps(request: @request)
            @request.event!('submitted', actor: @actor) if draft
            notify = true
          end
        end
      end
    end
    if notify
      if @request.pending?
        Oa::ApprovalNotifier.new(@request).submitted(resubmit: true)
      else
        Oa::ApprovalNotifier.new(@request).acted
      end
    end
    @request
  end

  private

  def validate_rules!(data)
    error = Crm::AttendanceApprovalService.overlap_violation(@request.account, @actor.id, @request.definition, data,
                                                             exclude_request_id: @request.id)
    raise Oa::FormValidator::InvalidForm, error if error
    return unless @request.definition.attendance_kind == 'reclock'

    date = Crm::AttendanceApprovalService.form_dates(@request.definition, data).first
    raise Oa::FormValidator::InvalidForm, '请填写补卡日期' unless date

    error = Crm::AttendanceApprovalService.reclock_violation(@request.account, @actor.id, date, exclude_request_id: @request.id)
    raise Oa::FormValidator::InvalidForm, error if error
  end
end
