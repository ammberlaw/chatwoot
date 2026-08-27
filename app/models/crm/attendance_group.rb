# == Schema Information
#
# Table name: crm_attendance_groups
#
#  id                  :bigint           not null, primary key
#  allowed_ips         :string           default([]), not null, is an Array
#  clock_in_time       :string           default("09:00"), not null
#  clock_out_time      :string           default("18:00"), not null
#  extra_workdays      :string           default([]), not null, is an Array
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
#  idx_crm_attendance_groups_single_default            (account_id) UNIQUE WHERE is_default
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
  # 开了校验却没配对应参数会把全员锁在门外——保存时就拦下。
  validate :geo_needs_office_coords
  validate :ip_needs_allowed_ips

  # 成员所属考勤组：命中成员列表的组，否则默认组。
  def self.for_user(account, user_id)
    account.crm_attendance_groups.where('? = ANY(user_ids)', user_id).first || default_for(account)
  end

  # 默认组：每账号唯一（有部分唯一索引保证）；并发首次创建靠 rescue 兜底。
  def self.default_for(account)
    account.crm_attendance_groups.find_or_create_by!(is_default: true) { |g| g.name = '默认考勤组' }
  rescue ActiveRecord::RecordNotUnique
    account.crm_attendance_groups.find_by!(is_default: true)
  end

  # 工作日 = 非节假日 且（周模式命中 或 调休补班日）。
  def work_day?(date)
    return false if holidays.include?(date.to_s)

    work_days.include?(date.cwday) || extra_workdays.include?(date.to_s)
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

  private

  def geo_needs_office_coords
    return unless geo_enabled? && (office_lat.blank? || office_lng.blank?)

    errors.add(:base, '开启 GPS 围栏需先设置办公坐标')
  end

  def ip_needs_allowed_ips
    return unless ip_enabled? && allowed_ips.reject(&:blank?).empty?

    errors.add(:base, '开启网络校验需至少填一个办公 IP')
  end
end
