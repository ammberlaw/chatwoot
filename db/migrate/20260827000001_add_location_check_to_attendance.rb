class AddLocationCheckToAttendance < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_attendance_groups, bulk: true do |t|
      # GPS 地理围栏打卡
      t.boolean :geo_enabled, default: false, null: false
      t.decimal :office_lat, precision: 10, scale: 7
      t.decimal :office_lng, precision: 10, scale: 7
      t.integer :geo_radius_m, default: 300, null: false
      # 办公网络(公网 IP)打卡 —— WiFi 打卡的网页等价方案
      t.boolean :ip_enabled, default: false, null: false
      t.string :allowed_ips, array: true, default: [], null: false
    end

    # 打卡时留存位置/网络，供审计与「打卡地点」展示
    change_table :crm_attendance_records, bulk: true do |t|
      t.string :clock_in_ip
      t.decimal :clock_in_lat, precision: 10, scale: 7
      t.decimal :clock_in_lng, precision: 10, scale: 7
      t.string :clock_out_ip
      t.decimal :clock_out_lat, precision: 10, scale: 7
      t.decimal :clock_out_lng, precision: 10, scale: 7
    end
  end
end
