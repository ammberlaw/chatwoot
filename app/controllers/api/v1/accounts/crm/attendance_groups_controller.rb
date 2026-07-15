# 考勤组管理（仅超级管理员与管理员）：增删改组与成员分配；一人只能属于一个组（分配时自动从其他组移除）。
class Api::V1::Accounts::Crm::AttendanceGroupsController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access
  before_action :ensure_admin_like
  before_action :fetch_group, only: [:update, :destroy]

  def index
    groups = Current.account.crm_attendance_groups.order(is_default: :desc, id: :asc)
    render json: { payload: groups.map { |g| group_json(g) } }
  end

  def create
    group = Current.account.crm_attendance_groups.create!(group_attrs)
    claim_members(group)
    render json: group_json(group)
  end

  def update
    @group.update!(group_attrs)
    claim_members(@group)
    render json: group_json(@group.reload)
  end

  def destroy
    return render json: { error: '默认考勤组不可删除' }, status: :unprocessable_entity if @group.is_default

    @group.destroy!
    head :ok
  end

  private

  def fetch_group
    @group = Current.account.crm_attendance_groups.find(params[:id])
  end

  def ensure_admin_like
    return if Current.account_user.administrator? || Current.account_user.crm_deputy_admin?

    render json: { error: '仅超级管理员或管理员可管理考勤组' }, status: :forbidden
  end

  def group_attrs
    g = params[:group]
    rule_attrs(g).merge(
      name: g[:name].to_s.strip,
      work_days: Array(g[:work_days]).map(&:to_i) & (1..7).to_a,
      holidays: Array(g[:holidays]).map(&:to_s).grep(/\A\d{4}-\d{2}-\d{2}\z/).uniq.sort,
      user_ids: Array(g[:user_ids]).map(&:to_i).uniq
    )
  end

  def rule_attrs(group_params)
    {
      clock_in_time: group_params[:clock_in_time],
      clock_out_time: group_params[:clock_out_time],
      grace_minutes: group_params[:grace_minutes].to_i,
      reclock_limit: group_params[:reclock_limit].to_i,
      reclock_window_days: group_params[:reclock_window_days].to_i
    }
  end

  # 一人一组：把本组新纳入的成员从其他组的成员列表中移除。
  def claim_members(group)
    return if group.user_ids.empty?

    Current.account.crm_attendance_groups.where.not(id: group.id).find_each do |other|
      overlap = other.user_ids & group.user_ids
      other.update!(user_ids: other.user_ids - overlap) if overlap.any?
    end
  end

  def group_json(group)
    { id: group.id, name: group.name, is_default: group.is_default,
      work_days: group.work_days, clock_in_time: group.clock_in_time,
      clock_out_time: group.clock_out_time, grace_minutes: group.grace_minutes,
      reclock_limit: group.reclock_limit, reclock_window_days: group.reclock_window_days,
      holidays: group.holidays, user_ids: group.user_ids }
  end
end
