class AddCompletedDatesToCrmScheduleEvents < ActiveRecord::Migration[7.1]
  def change
    # 按「发生日期」记录完成——重复日程可按次打勾（这周完成不影响下周）。
    add_column :crm_schedule_events, :completed_dates, :date, array: true, null: false, default: []
  end
end
