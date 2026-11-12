class Api::V1::Accounts::Crm::KpiSchemesController < Api::V1::Accounts::Crm::BaseController
  # HR 板块：人事部成员可能没有 CRM 角色，放行 CRM 门禁，可见性由 KpiSchemePolicy 管。
  skip_before_action :ensure_crm_access
  before_action :check_authorization
  before_action :fetch_scheme, only: [:show, :update, :destroy, :distribute, :duplicate]

  def index
    @schemes = Current.account.crm_kpi_schemes
                      .includes(:scheme_items, :payout_tiers, :created_by)
                      .order(scheme_month: :desc)
  end

  def show; end

  def create
    @scheme = Current.account.crm_kpi_schemes.new(scalar_params)
    @scheme.created_by = Current.user
    assign_children(@scheme)
    assign_detail_tables(@scheme)
    @scheme.save!
  end

  def update
    @scheme.assign_attributes(scalar_params)
    assign_children(@scheme)
    assign_detail_tables(@scheme)
    @scheme.save!
  end

  def destroy
    @scheme.destroy!
    head :ok
  end

  # 下发：为选中员工各生成一张当月考核表（已存在的跳过），并置方案为已下发。
  def distribute
    owner_ids = Array(params[:owner_ids]).map(&:to_i).uniq
    month = @scheme.scheme_month
    existing = Current.account.crm_kpi_sheets
                      .where(crm_kpi_scheme_id: @scheme.id, owner_id: owner_ids)
                      .for_month(month).pluck(:owner_id)
    created = (owner_ids - existing).map { |uid| build_sheet_for(uid, month) }
    @scheme.update!(status: 'PUBLISHED') if created.any? && @scheme.status != 'PUBLISHED'
    notify_distributed(created)
    render json: { created: created.size, skipped: existing.size }
  end

  # 复制方案：整份拷贝（含指标/发放档/明细表），名字加「(副本)」，状态回草稿、创建人=当前用户。
  def duplicate
    copy = Current.account.crm_kpi_schemes.new(
      @scheme.attributes.slice('scheme_month', 'pass_score', 'item_score_cap_pct', 'total_score_cap',
                               'payout_note', 'result_note', 'detail_tables')
    )
    copy.name = "#{@scheme.name} (副本)"
    copy.status = 'DRAFT'
    copy.created_by = Current.user
    copy.scheme_items = @scheme.scheme_items.map(&:dup)
    copy.payout_tiers = @scheme.payout_tiers.map(&:dup)
    copy.save!
    @scheme = copy
    render :show
  end

  private

  # 下发后自动在团队沟通提醒每位新下发的成员（已存在跳过的不重复提醒）。
  def notify_distributed(sheets)
    return if sheets.empty?

    notifier = Chat::NotifyService.new(account: Current.account, sender: Crm::SystemUser.for(Current.account))
    sheets.each do |sheet|
      notifier.notify(
        sheet.owner_id,
        "【绩效考核】#{sheet.scheme_name} 已下发，请及时到「考核表」填报本月绩效考核。",
        ref: { type: 'kpi_sheet', id: sheet.id, label: '考核表',
               title: sheet.scheme_name, subtitle: '已下发 · 待你填报' }
      )
    end
  end

  # 快照方案 + 员工薪资，复制指标行，生成一张考核表。
  def build_sheet_for(owner_id, month)
    comp = Current.account.crm_employee_comps.current.owned_by(owner_id).order(created_at: :desc).first
    sheet = Current.account.crm_kpi_sheets.create!(
      crm_kpi_scheme_id: @scheme.id, owner_id: owner_id, scheme_name: @scheme.name,
      period_month: month, status: 'PENDING', pass_score: @scheme.pass_score,
      item_score_cap_pct: @scheme.item_score_cap_pct,
      total_score_cap: @scheme.total_score_cap,
      payout_note: @scheme.payout_note, result_note: @scheme.result_note,
      monthly_salary_micros: comp&.monthly_salary_micros, performance_ratio: comp&.performance_ratio,
      baseline_target_micros: comp&.baseline_target_micros
    )
    @scheme.scheme_items.sort_by { |i| [i.sort_order || 0, i.id] }.each do |it|
      sheet.sheet_items.create!(
        name: it.name, dimension: it.dimension, standard: it.standard, weight: it.weight,
        baseline_value: it.baseline_value, target_value: it.target_value,
        data_source: it.data_source, sort_order: it.sort_order,
        # 指标级上限随方案一起拍快照；留空则计分时回落方案级（见 KpiSheetsController#score_cap_ratio）
        score_cap_pct: it.score_cap_pct
      )
    end
    sheet
  end

  def fetch_scheme
    @scheme = Current.account.crm_kpi_schemes.includes(:scheme_items, :payout_tiers).find(params[:id])
  end

  def check_authorization
    authorize(Crm::KpiScheme)
  end

  def scalar_params
    params.require(:scheme).permit(:name, :scheme_month, :pass_score, :item_score_cap_pct, :total_score_cap, :payout_note, :result_note, :status)
  end

  # 明细表结构自由（JSONB），逐层收敛成 title/columns/rows 纯字符串结构。
  def assign_detail_tables(scheme)
    return unless params[:scheme].key?(:detail_tables)

    scheme.detail_tables = Array(params[:scheme][:detail_tables]).map do |t|
      {
        'title' => t[:title].to_s,
        'columns' => Array(t[:columns]).map(&:to_s),
        'rows' => Array(t[:rows]).map { |row| Array(row).map(&:to_s) }
      }
    end
  end

  # 指标 / 发放档随方案整组替换（前端传全量数组；account_id 由子模型从方案继承）。
  def assign_children(scheme)
    scheme.scheme_items = build_items if params[:scheme].key?(:scheme_items)
    scheme.payout_tiers = build_tiers if params[:scheme].key?(:payout_tiers)
  end

  def build_items
    Array(params[:scheme][:scheme_items]).map do |raw|
      Crm::SchemeItem.new(raw.permit(:name, :dimension, :standard, :weight, :baseline_value,
                                     :target_value, :data_source, :sort_order, :score_cap_pct))
    end
  end

  def build_tiers
    Array(params[:scheme][:payout_tiers]).map do |raw|
      Crm::PayoutTier.new(raw.permit(:name, :min_score, :max_score, :coefficient, :proportional, :sort_order))
    end
  end
end
