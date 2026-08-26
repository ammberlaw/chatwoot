# == Schema Information
#
# Table name: crm_attendance_groups
#
#  id                  :bigint           not null, primary key
#  allowed_ips         :string           default([]), not null, is an Array
#  clock_in_time       :string           default("09:00"), not null
#  clock_out_time      :string           default("18:00"), not null
#  geo_enabled         :boolean          default(FALSE), not null
#  geo_radius_m        :integer          default(300), not null
#  grace_minutes       :integer          default(0), not null
#  holidays            :string           default([]), not null, is an Array
#  ip_enabled          :boolean          default(FALSE), not null
#  is_default          :boolean          default(FALSE), not null
#  name                :string           not null
#  office_lat          :decimal(10, 7)
#  office_lng          :decimal(10, 7)
#  reclock_limit       :integer          default(3), not null
#  reclock_window_days :integer          default(30), not null
#  user_ids            :bigint           default([]), not null, is an Array
#  work_days           :integer          default([1, 2, 3, 4, 5]), not null, is an Array
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_crm_attendance_groups_on_account_id           (account_id)
#  index_crm_attendance_groups_on_account_id_and_name  (account_id,name) UNIQUE
#

# 考勤组：一组人共用一套考勤规则；未分组成员按默认组执行。
class Crm::AttendanceGroup < ApplicationRecord
  belongs_to :account

  audited

  TIME_FORMAT = /\A\d{2}:\d{2}\z/
  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :clock_in_time, :clock_out_time, format: { with: TIME_FORMAT }
  validates :grace_minutes, :reclock_limit, :reclock_window_days, numericality: { greater_than_or_equal_to: 0 }

  # 成员所属考勤组：命中成员列表的组，否则默认组。
  def self.for_user(account, user_id)
    account.crm_attendance_groups.where('? = ANY(user_ids)', user_id).first || default_for(account)
  end

  def self.default_for(account)
    account.crm_attendance_groups.find_by(is_default: true) ||
      account.crm_attendance_groups.create!(name: '默认考勤组', is_default: true)
  end

  def work_day?(date)
    work_days.include?(date.cwday) && holidays.exclude?(date.to_s)
  end

  # 'HH:MM' → 当日分钟数
  def self.minutes(hhmm)
    h, m = hhmm.split(':').map(&:to_i)
    (h * 60) + m
  end

  # 是否开启了打卡地点/网络校验（都没开=不限制，沿用旧行为）。
  def location_required?
    geo_enabled? || ip_enabled?
  end

  # 打卡地点校验：命中「办公网络 IP」或「GPS 在围栏内」任一即通过。
  def location_ok?(lat:, lng:, ip:)
    return true unless location_required?
    return true if ip_enabled? && ip.present? && allowed_ips.include?(ip.to_s)
    if geo_enabled? && office_lat && office_lng && lat.present? && lng.present?
      return true if distance_meters(lat.to_f, lng.to_f, office_lat.to_f, office_lng.to_f) <= geo_radius_m
    end
    false
  end

  # 两坐标间球面距离（米，Haversine）。
  def distance_meters(lat1, lng1, lat2, lng2)
    rad = Math::PI / 180
    earth = 6_371_000
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad
    a = (Math.sin(dlat / 2)**2) +
        (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
    2 * earth * Math.asin(Math.sqrt(a))
  end
end
