class AddRefToCrmScheduleEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_schedule_events, :ref_type, :string
    add_column :crm_schedule_events, :ref_id, :bigint
    add_index :crm_schedule_events, [:account_id, :ref_type, :ref_id]
  end
end
