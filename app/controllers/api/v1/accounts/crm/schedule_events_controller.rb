# 日程 Schedule 控制器。全员可用（不走 CRM 门禁，直接继承账号基类）：
# 每人只看/管自己创建 + 被邀参与的日程；改/删仅创建者。
class Api::V1::Accounts::Crm::ScheduleEventsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_event, only: [:update, :destroy, :toggle_done, :complete_follow_up]

  # 按 from/to 窗口返回展开后的日程发生（含重复）。默认本月。
  def index
    win_start = params[:from].present? ? Time.zone.parse(params[:from]) : Time.zone.now.beginning_of_month
    win_end = params[:to].present? ? Time.zone.parse(params[:to]).end_of_day : Time.zone.now.end_of_month
    events = Current.account.crm_schedule_events
                    .visible_to(current_user.id)
                    .includes(:owner, :participant_users, :customer)
    @occurrences = events.flat_map do |ev|
      ev.occurrences_in(win_start, win_end).map do |occ|
        { event: ev, starts_at: occ[:starts_at], ends_at: occ[:ends_at] }
      end
    end.sort_by { |o| o[:starts_at] }
  end

  def create
    @event = Current.account.crm_schedule_events.new(event_params.merge(owner_id: current_user.id))
    @event.save!
    sync_participants(@event)
    render :show
  end

  def update
    @event.update!(event_params)
    sync_participants(@event)
    render :show
  end

  def destroy
    @event.destroy!
    head :ok
  end

  # 侧栏角标：本人可见、今日到期或已逾期、且未打勾的日程发生数（近 60 天窗口内展开重复）。
  def pending_count
    today = Time.zone.today
    win_start = (today - 60).beginning_of_day
    win_end = today.end_of_day
    count = Current.account.crm_schedule_events.visible_to(current_user.id).sum do |ev|
      done = ev.completed_dates.map(&:to_s)
      ev.occurrences_in(win_start, win_end).count { |occ| done.exclude?(occ[:starts_at].to_date.to_s) }
    end
    render json: { count: count }
  end

  # 在日程里直接完成一条「跟进提醒」：落一条客户跟进记录，并把提醒顺延到下次跟进时间（清空则删除提醒）。
  def complete_follow_up
    customer = Current.account.crm_customers.find(@event.customer_id)
    Current.account.crm_follow_up_notes.create!(
      title: "跟进：#{customer.name}",
      body: params[:body],
      follow_up_method: params[:follow_up_method].presence,
      result_tag: params[:result_tag].presence,
      crm_customer_id: customer.id,
      owner_id: current_user.id
    )
    next_at = params[:next_follow_up_at]
    customer.update_columns(next_follow_up_at: next_at.presence, updated_at: Time.current)
    Crm::ScheduleEvent.sync_follow_up(Current.account, customer, next_at, next_at.present?, current_user.id)
    head :ok
  end

  # 按「发生日期」切换完成状态（重复日程按次打勾）。
  def toggle_done
    date = params[:date].to_s
    dates = @event.completed_dates.map(&:to_s)
    next_dates = dates.include?(date) ? dates - [date] : dates + [date]
    @event.update_columns(completed_dates: next_dates)
    head :ok
  end

  private

  def fetch_event
    @event = Current.account.crm_schedule_events.where(owner_id: current_user.id).find(params[:id])
  end

  # participant_ids 传入即全量覆盖参与人（排除创建者本人）。未传则不动。
  def sync_participants(event)
    raw = params.require(:schedule_event)[:participant_ids]
    return if raw.nil?

    ids = Array(raw).map(&:to_i).uniq - [event.owner_id]
    event.participants.where.not(user_id: ids).destroy_all
    (ids - event.participants.pluck(:user_id)).each { |uid| event.participants.create!(user_id: uid) }
  end

  def check_authorization
    authorize(Crm::ScheduleEvent)
  end

  def event_params
    params.require(:schedule_event).permit(
      :title, :starts_at, :ends_at, :all_day, :location, :note, :color, :recurrence, :recurrence_until,
      :ref_type, :ref_id
    )
  end
end
