require 'rails_helper'

# 半天假的判定口径。它同时决定两件事：提交时算出来的 leave_days（0.5 天，条件路由要用）
# 和审批通过时写进考勤的状态（HALF_LEAVE vs LEAVE）——而考勤直接进考勤统计与工资，
# 所以这些边界必须钉死在测试里。
#
# 午休把一天切成不等长的两段（09:00-18:00 配 12:00-13:30 午休 → 上午 3h、下午 4.5h），
# 所以「下午请假」不能靠「时长是否过半」来认，下面按段/按时长两类用例分开盖。
RSpec.describe Crm::AttendanceApprovalService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:datetime_fields) do
    [{ 'key' => 'leave_type', 'type' => 'select', 'options' => %w[事假 上午 下午] },
     { 'key' => 'start_date', 'type' => 'datetime' },
     { 'key' => 'end_date', 'type' => 'datetime' }]
  end

  # 只有 form_fields 会被读到，用轻量替身避免为模板补一整套 factory。
  def template(fields)
    instance_double(Oa::ApprovalTemplate, form_fields: fields)
  end

  def half_day?(start_at, end_at, extra = {}, fields: datetime_fields)
    described_class.half_day?(account, user.id,
                              template(fields),
                              { 'start_date' => start_at, 'end_date' => end_at }.merge(extra))
  end

  # 深圳班：09:00–18:30，午休 12:00–13:30 → 上午 3h、下午 5h，全天 8h。
  context 'with a 09:00–18:30 shift (深圳)' do
    before do
      Crm::AttendanceGroup.default_for(account)
                          .update!(clock_in_time: '09:00', clock_out_time: '18:30',
                                   break_start_time: '12:00', break_end_time: '13:30')
    end

    it 'treats a morning-only leave as half a day' do
      expect(half_day?('2026-10-12T09:00', '2026-10-12T12:00')).to be(true)
    end

    it 'treats an afternoon-only leave as half a day even though it is the longer half' do
      expect(half_day?('2026-10-12T13:30', '2026-10-12T18:30')).to be(true)
    end

    it 'treats a partial afternoon as half a day' do
      expect(half_day?('2026-10-12T15:00', '2026-10-12T18:30')).to be(true)
    end

    it 'ignores hours outside the working window' do
      # 07:00–12:00 里只有 09:00–12:00 是上班时间 → 仍是上午半天。
      expect(half_day?('2026-10-12T07:00', '2026-10-12T12:00')).to be(true)
    end

    it 'counts a whole workday as a full day' do
      expect(half_day?('2026-10-12T09:00', '2026-10-12T18:30')).to be(false)
    end

    it 'measures leaves that straddle lunch by net working time' do
      # 09:00–14:00 = 上午 3h + 下午 0.5h = 3.5h ≤ 4h → 半天。
      expect(half_day?('2026-10-12T09:00', '2026-10-12T14:00')).to be(true)
      # 09:00–16:00 = 3h + 2.5h = 5.5h > 4h → 整天。
      expect(half_day?('2026-10-12T09:00', '2026-10-12T16:00')).to be(false)
    end

    it 'does not charge the lunch break itself' do
      # 12:00–13:30 全在午休里，一分钟班都没耽误。
      expect(half_day?('2026-10-12T12:00', '2026-10-12T13:30')).to be(true)
    end

    it 'lets duration override a 时段 keyword that says otherwise' do
      expect(half_day?('2026-10-12T09:00', '2026-10-12T18:30', { 'leave_type' => '上午' })).to be(false)
    end
  end

  # 东莞班：08:30–17:30，同样午休 12:00–13:30 → 上午 3.5h、下午 4h，全天 7.5h。
  context 'with a 08:30–17:30 shift (东莞)' do
    before do
      account.crm_attendance_groups.create!(name: '东莞考勤组', clock_in_time: '08:30', clock_out_time: '17:30',
                                            break_start_time: '12:00', break_end_time: '13:30', user_ids: [user.id])
    end

    it 'measures against that shift, not the default one' do
      expect(half_day?('2026-10-12T13:30', '2026-10-12T17:30')).to be(true)
      expect(half_day?('2026-10-12T08:30', '2026-10-12T17:30')).to be(false)
      # 10:00–17:30 = 2h + 4h = 6h > 3.75h → 整天。
      expect(half_day?('2026-10-12T10:00', '2026-10-12T17:30')).to be(false)
    end
  end

  # 不设午休的组：整天算一段，回到「有效时长是否过半」。
  context 'with no lunch break configured' do
    before do
      Crm::AttendanceGroup.default_for(account)
                          .update!(clock_in_time: '09:00', clock_out_time: '18:00',
                                   break_start_time: '', break_end_time: '')
    end

    it 'splits at exactly half the workday' do
      expect(half_day?('2026-10-12T09:00', '2026-10-12T13:30')).to be(true)
      expect(half_day?('2026-10-12T09:00', '2026-10-12T13:31')).to be(false)
    end
  end

  # 旧模板只有纯日期字段，判不出时长——回退到「选择/文本字段填了上午/下午/半天」。
  context 'when the template carries no times' do
    let(:date_fields) do
      [{ 'key' => 'leave_type', 'type' => 'select', 'options' => %w[事假 上午] },
       { 'key' => 'start_date', 'type' => 'date' },
       { 'key' => 'end_date', 'type' => 'date' }]
    end

    it 'falls back to the 时段 keyword' do
      expect(half_day?('2026-10-12', '2026-10-12', { 'leave_type' => '上午' }, fields: date_fields)).to be(true)
      expect(half_day?('2026-10-12', '2026-10-12', { 'leave_type' => '事假' }, fields: date_fields)).to be(false)
    end
  end
end
