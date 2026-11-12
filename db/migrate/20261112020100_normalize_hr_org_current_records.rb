class NormalizeHrOrgCurrentRecords < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE crm_employee_comps SET active = false WHERE id IN (
        SELECT id FROM (
          SELECT id, row_number() OVER (PARTITION BY account_id, owner_id ORDER BY created_at DESC, id DESC) AS position
          FROM crm_employee_comps WHERE owner_id IS NOT NULL
        ) ranked WHERE position > 1
      )
    SQL
    execute 'UPDATE crm_employee_comps SET effective_on = created_at::date WHERE effective_on IS NULL'
    execute <<~SQL
      UPDATE org_memberships SET is_primary = false WHERE id IN (
        SELECT id FROM (
          SELECT id, row_number() OVER (PARTITION BY account_id, user_id ORDER BY updated_at DESC, id DESC) AS position
          FROM org_memberships WHERE is_primary = true
        ) ranked WHERE position > 1
      )
    SQL
  end

  # Keep preserved history and normalized current flags on rollback.
  def down; end
end
