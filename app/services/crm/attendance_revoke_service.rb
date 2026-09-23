# 销假：把某张已通过的考勤类审批单写进去的考勤记录撤回。
#
# 四条铁律（写死在这里，不靠调用方自觉）：
#   1. 只删本单写的 —— 认 approval_request_id，不按日期猜。同一天可能被多张单写过
#      （先请假、后补卡），按日期删必然误伤。
#   2. 只销今天及以后 —— 过去的日子人确实没来上班，销掉等于把考勤改成「正常」，
#      是伪造记录。要改历史走 HR 手工修正（source=hr，优先级本来就更高）。
#   3. 不碰 HR 改过的 —— source 已不是 approval，说明 HR 后来手工修正过，以 HR 为准。
#   4. 不碰已实打卡的 —— 有 clock_in_at 说明人实际来了，删掉会丢真实打卡数据；
#      这种只把状态退回 NORMAL，打卡时间原样保留。
class Crm::AttendanceRevokeService
  class RevokeError < StandardError; end

  Result = Struct.new(:removed_dates, :reset_dates, keyword_init: true)

  def initialize(request:, from:, to:, actor:)
    @request = request
    @from = from
    @to = to
    @actor = actor
  end

  def perform
    raise RevokeError, '销假区间不合法' if @from.nil? || @to.nil? || @from > @to

    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    from = [@from, today].max
    raise RevokeError, '只能销今天及以后的假，历史考勤请走 HR 修正' if from > @to

    removed = []
    reset = []
    scope.where(work_date: from..@to).find_each do |rec|
      if rec.clock_in_at.present?
        # 人实际来打了卡：保住打卡数据，只把「请假/外出」状态退回正常
        rec.update!(status: 'NORMAL', field: false, source: 'approval',
                    note: "销假：#{@request.title}", adjusted_by_id: @actor.id)
        reset << rec.work_date
      else
        rec.destroy!
        removed << rec.work_date
      end
    end
    Result.new(removed_dates: removed, reset_dates: reset)
  end

  private

  # 只认本单写的、且仍是审批来源的记录（HR 改过的 source 已变，自动排除）。
  def scope
    @request.account.crm_attendance_records
            .where(approval_request_id: @request.id, source: 'approval')
            .order(:work_date)
  end
end
