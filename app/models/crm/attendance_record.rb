# == Schema Information
#
# Table name: crm_attendance_records
#
#  id             :bigint           not null, primary key
#  clock_in_at    :datetime
#  clock_out_at   :datetime
#  note           :string
#  status         :string           default("NORMAL"), not null
#  work_date      :date             not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  adjusted_by_id :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  idx_crm_attendance_on_user_date                           (account_id,user_id,work_date) UNIQUE
#  index_crm_attendance_records_on_account_id_and_work_date  (account_id,work_date)
#

# 每日打卡记录：每人每天一条；状态由打卡时间按规则判定，HR 修正（adjusted_by）后不再自动改写。
class Crm::AttendanceRecord < ApplicationRecord
  # 打卡与工作日均按中国时区口径。
  TZ = 'Asia/Shanghai'.freeze
  STATUSES = %w[NORMAL LATE EARLY_LEAVE LATE_EARLY ABSENT LEAVE].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :adjusted_by, class_name: 'User', optional: true

  # HR 修正留痕。
  audited

  validates :work_date, uniqueness: { scope: [:account_id, :user_id] }
  validates :status, inclusion: { in: STATUSES }

  # 按规则重算状态（迟到/早退/两者/正常）；已被 HR 修正的不动。
  def recompute_status!(setting)
    return if adjusted_by_id

    late = late?(setting)
    early = early_leave?(setting)
    self.status = if late && early
                    'LATE_EARLY'
                  elsif late
                    'LATE'
                  elsif early
                    'EARLY_LEAVE'
                  else
                    'NORMAL'
                  end
  end

  private

  def late?(setting)
    clock_in_at && local_minutes(clock_in_at) > Crm::AttendanceSetting.minutes(setting.clock_in_time) + setting.grace_minutes
  end

  def early_leave?(setting)
    clock_out_at && local_minutes(clock_out_at) < Crm::AttendanceSetting.minutes(setting.clock_out_time) - setting.grace_minutes
  end

  def local_minutes(time)
    local = time.in_time_zone(TZ)
    (local.hour * 60) + local.min
  end
end
