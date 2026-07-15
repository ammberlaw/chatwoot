# == Schema Information
#
# Table name: crm_attendance_groups
#
#  id                  :bigint           not null, primary key
#  clock_in_time       :string           default("09:00"), not null
#  clock_out_time      :string           default("18:00"), not null
#  grace_minutes       :integer          default(0), not null
#  holidays            :string           default([]), not null, is an Array
#  is_default          :boolean          default(FALSE), not null
#  name                :string           not null
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
end
