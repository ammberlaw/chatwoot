class CreateCrmScheduleEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_schedule_events do |t|
      t.bigint :account_id, null: false
      t.bigint :owner_id, null: false
      t.string :title, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :all_day, null: false, default: false
      t.string :location
      t.text :note
      t.string :color, null: false, default: 'blue'
      t.string :recurrence, null: false, default: 'none' # none / daily / weekly / monthly
      t.date :recurrence_until
      t.timestamps
    end
    add_index :crm_schedule_events, [:account_id, :owner_id]
    add_index :crm_schedule_events, [:account_id, :starts_at]

    create_table :crm_schedule_participants do |t|
      t.bigint :crm_schedule_event_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end
    add_index :crm_schedule_participants, [:crm_schedule_event_id, :user_id],
              unique: true, name: 'idx_crm_sched_participant'
    add_index :crm_schedule_participants, :user_id
  end
end
