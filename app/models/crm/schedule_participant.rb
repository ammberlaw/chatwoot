# 日程参与人：被邀请的成员，在自己的日历里也能看到该日程。
# == Schema Information
#
# Table name: crm_schedule_participants
#
#  id                    :bigint           not null, primary key
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  crm_schedule_event_id :bigint           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  idx_crm_sched_participant                   (crm_schedule_event_id,user_id) UNIQUE
#  index_crm_schedule_participants_on_user_id  (user_id)
#
class Crm::ScheduleParticipant < ApplicationRecord
  belongs_to :schedule_event, class_name: 'Crm::ScheduleEvent',
                              foreign_key: :crm_schedule_event_id, inverse_of: :participants
  belongs_to :user

  validates :user_id, uniqueness: { scope: :crm_schedule_event_id }
end
