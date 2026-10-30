class Api::V1::Accounts::Crm::SalesTargetsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_target, only: [:show, :update, :destroy]

  def index
    @targets_scope = filtered_targets
    @targets = @targets_scope.order(target_month: :desc)
  end

  def show; end

  def create
    @target = Current.account.crm_sales_targets.create!(target_params.merge(owner_id: target_params[:owner_id] || current_user.id))
  end

  def update
    @target.update!(target_params)
  end

  def destroy
    @target.destroy!
    head :ok
  end

  # 目标体检：谁本月没设、谁当年合计低于保本线×12。
  def audit
    audit = Crm::SalesTargetAudit.new(account: Current.account, year: params[:year])
    render json: { year: audit_year, rows: audit.rows.map { |row| row_payload(row) },
                   orphans: audit.orphans.map { |t| orphan_payload(t) } }
  end

  # 一键按底线补：只补缺的月份，已有目标一律不动。
  def seed
    outcome = Crm::SalesTargetSeeder.new(
      account: Current.account, owner_ids: seed_owner_ids, year: audit_year,
      options: { source: params[:source], from_month: params[:from_month] }
    ).call
    render json: { created: outcome.created, skipped: outcome.skipped,
                   blocked: outcome.blocked.map { |b| b.merge(name: user_names[b[:owner_id]]) } }
  end

  private

  def audit_year = (params[:year] || Time.zone.today.year).to_i

  def user_names
    @user_names ||= User.where(id: sales_owner_ids).pluck(:id, :name).to_h
  end

  # 在职业务员。前端传来的 owner_ids 一律在这里过筛，防止给任意账号塞目标。
  def sales_owner_ids
    @sales_owner_ids ||= Current.account.account_users.where(crm_role: 'sales').pluck(:user_id)
  end

  def seed_owner_ids
    asked = Array(params[:owner_ids]).map(&:to_i)
    asked.presence ? (asked & sales_owner_ids) : sales_owner_ids
  end

  # 保本线相关的字段只给到这一层：露出底线数字和有效提成率，**不露月薪**。
  def row_payload(row)
    base = row.baseline
    { owner_id: row.owner_id, name: row.name, months_set: row.months_set,
      year_total_micros: row.year_total_micros, current_month_micros: row.current_month_micros,
      missing_current_month: row.missing_current_month?,
      year_required_micros: row.year_required_micros, shortfall_micros: row.shortfall_micros,
      tenure_months: base&.tenure_months, new_hire: base&.new_hire? || false,
      recorded_micros: base&.recorded_micros, suggested_micros: base&.suggested_micros,
      effective_rate: base&.effective_rate, off_by_ratio: base&.off_by_ratio,
      blockers: base&.blockers || [], notes: base&.notes || [] }
  end

  def orphan_payload(target)
    { id: target.id, owner_name: target.owner&.name,
      target_month: target.target_month, target_amount_micros: target.target_amount_micros }
  end

  # 按归属收口：业务员只能取/改自己的目标，主管取本部门，管理员/副管全部。
  def fetch_target
    @target = scope_by_owner(Current.account.crm_sales_targets).find(params[:id])
  end

  def check_authorization
    authorize(Crm::SalesTarget)
  end

  # 我的目标 / 按月份。列表按归属收口，防止业务员看到全员业绩指标。
  def filtered_targets
    scope = scope_by_owner(Current.account.crm_sales_targets)
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.for_month(Date.parse(params[:month])) if params[:month].present?
    scope
  end

  def target_params
    params.require(:target).permit(:name, :target_month, :target_amount_micros, :target_order_count, :owner_id)
  end
end
