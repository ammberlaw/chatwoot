# 日程 Schedule：个人日历事件，可邀参与人（被邀人在自己日历也能看到）。支持每日/每周/每月重复。
# 重复事件不落地成多行，查询时按窗口展开为具体发生日（v1 改/删按整条系列，不做单次例外）。
# == Schema Information
#
# Table name: crm_schedule_events
#
#  id               :bigint           not null, primary key
#  all_day          :boolean          default(FALSE), not null
#  color            :string           default("blue"), not null
#  completed_dates  :date             default([]), not null, is an Array
#  ends_at          :datetime         not null
#  kind             :string           default("manual"), not null
#  location         :string
#  note             :text
#  recurrence       :string           default("none"), not null
#  recurrence_until :date
#  ref_type         :string
#  starts_at        :datetime         not null
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  customer_id      :bigint
#  owner_id         :bigint           not null
#  ref_id           :bigint
#
# Indexes
#
#  idx_on_account_id_ref_type_ref_id_0ed352b1aa             (account_id,ref_type,ref_id)
#  index_crm_schedule_events_on_account_id_and_customer_id  (account_id,customer_id)
#  index_crm_schedule_events_on_account_id_and_owner_id     (account_id,owner_id)
#  index_crm_schedule_events_on_account_id_and_starts_at    (account_id,starts_at)
#
class Crm::ScheduleEvent < ApplicationRecord
  COLORS = %w[blue teal violet rose lime sky].freeze
  RECURRENCES = %w[none daily weekly monthly].freeze
  # 关联对象（可空）：日程可挂到客户 / 商机 / 订单，点开跳到对应页面。
  REF_TYPES = %w[customer opportunity order].freeze
  REF_CLASS = { 'customer' => 'Crm::Customer', 'opportunity' => 'Crm::Opportunity', 'order' => 'Crm::SalesOrder' }.freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User'
  belongs_to :customer, class_name: 'Crm::Customer', optional: true
  has_many :participants, class_name: 'Crm::ScheduleParticipant',
                          foreign_key: :crm_schedule_event_id, inverse_of: :schedule_event, dependent: :destroy
  has_many :participant_users, through: :participants, source: :user

  validates :title, presence: true
  validates :starts_at, :ends_at, presence: true
  validates :color, inclusion: { in: COLORS }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :ref_type, inclusion: { in: REF_TYPES }, allow_blank: true
  validate :ends_after_starts

  # 关联对象的展示名（订单优先 name，无则单号）；无关联返回 nil。
  def ref_name
    record = ref_record
    return if record.nil?
    return record.name unless ref_type == 'order'

    record.name.presence || record.order_no
  end

  # 当前用户可见：本人创建 或 被邀参与。
  scope :visible_to, lambda { |user_id|
    left_joins(:participants)
      .where('crm_schedule_events.owner_id = :u OR crm_schedule_participants.user_id = :u', u: user_id)
      .distinct
  }

  # 同步「跟进提醒」日程：每个客户至多一条 kind=follow_up 事件（幂等，重复保存只更新不新增）。
  # add 为假或时间清空时删除该提醒；事件归属客户负责人（无则 fallback_owner_id）。
  def self.sync_follow_up(account, customer, at, add, fallback_owner_id)
    event = account.crm_schedule_events.find_or_initialize_by(customer_id: customer.id, kind: 'follow_up')
    if at.blank? || !ActiveModel::Type::Boolean.new.cast(add)
      event.destroy if event.persisted?
      return
    end
    starts = Time.zone.parse(at.to_s)
    event.assign_attributes(
      owner_id: customer.account_owner_id || fallback_owner_id,
      title: "跟进客户：#{customer.name}",
      starts_at: starts, ends_at: starts + 30.minutes,
      color: 'rose', recurrence: 'none', all_day: false,
      note: "客户跟进提醒 · #{customer.name}"
    )
    event.save!
  end

  # 在 [win_start, win_end] 窗口内展开重复，返回具体发生的 [{starts_at:, ends_at:}]。
  def occurrences_in(win_start, win_end)
    duration = ends_at - starts_at
    cap = recurrence_until ? [win_end, recurrence_until.end_of_day].min : win_end
    starts = collect_starts(win_start, cap)
    starts.map { |s| { starts_at: s, ends_at: s + duration } }
  end

  private

  # 关联记录（账号内按 ref_type/ref_id 找）；无则 nil。
  def ref_record
    return if ref_type.blank? || ref_id.blank?

    REF_CLASS[ref_type]&.constantize&.find_by(account_id: account_id, id: ref_id)
  end

  def collect_starts(win_start, cap)
    return starts_at.between?(win_start, cap) ? [starts_at] : [] if recurrence == 'none'

    step = { 'daily' => 1.day, 'weekly' => 1.week, 'monthly' => 1.month }[recurrence]
    out = []
    cursor = starts_at
    guard = 0
    while cursor <= cap && guard < 2000
      out << cursor if cursor >= win_start
      cursor += step
      guard += 1
    end
    out
  end

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?

    errors.add(:ends_at, '结束时间需晚于开始时间') if ends_at < starts_at
  end
end
