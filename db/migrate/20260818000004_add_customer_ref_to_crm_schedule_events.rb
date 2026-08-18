class AddCustomerRefToCrmScheduleEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_schedule_events, :customer_id, :bigint
    add_column :crm_schedule_events, :kind, :string, null: false, default: 'manual'
    add_index :crm_schedule_events, [:account_id, :customer_id]
  end
end
