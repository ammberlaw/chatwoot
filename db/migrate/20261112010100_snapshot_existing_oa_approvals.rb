class SnapshotExistingOaApprovals < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE oa_approval_requests r SET template_snapshot =
        jsonb_build_object('id', t.id, 'name', t.name, 'revision', t.revision, 'form_fields', t.form_fields,
          'flow', t.flow, 'attendance_kind', t.attendance_kind, 'cash_kind', t.cash_kind,
          'erp_expense', t.erp_expense, 'cc_user_ids', t.cc_user_ids, 'auto_approve', t.auto_approve,
          'overdue_hours', t.overdue_hours, 'legacy', true)
      FROM oa_approval_templates t WHERE t.id = r.template_id AND r.template_snapshot = '{}'::jsonb
    SQL
    # Already completed requests must never replay historical attendance/cash effects.
    execute "UPDATE oa_approval_requests SET finalized_at = updated_at WHERE status = 'approved' AND finalized_at IS NULL"
  end

  def down
    # Retain captured history; a rollback must not erase the only saved definition.
  end
end
