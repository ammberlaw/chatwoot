# == Schema Information
#
# Table name: crm_attendance_settings
#
#  id             :bigint           not null, primary key
#  clock_in_time  :string           default("09:00"), not null
#  clock_out_time :string           default("18:00"), not null
#  grace_minutes  :integer          default(0), not null
#  holidays       :string           default([]), not null, is an Array
#  work_days      :integer          default([1, 2, 3, 4, 5]), not null, is an Array
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_crm_attendance_settings_on_account_id  (account_id) UNIQUE
#

# 考勤规则（单行/账号）：工作日、上下班时间、迟到早退宽限分钟。
class Crm::AttendanceSetting < ApplicationRecord
  belongs_to :account

  audited

  TIME_FORMAT = /\A\d{2}:\d{2}\z/
  validates :clock_in_time, :clock_out_time, format: { with: TIME_FORMAT }
  validates :grace_minutes, numericality: { greater_than_or_equal_to: 0 }

  def self.for_account(account)
    find_or_create_by!(account: account)
  end

  def work_day?(date)
    work_days.include?(date.cwday) && holidays.exclude?(date.to_s)
  end

  # 'HH:MM' → 当日分钟数
  def self.minutes(hhmm)
    h, m = hhmm.split(':').map(&:to_i)
    (h * 60) + m
  end
end
