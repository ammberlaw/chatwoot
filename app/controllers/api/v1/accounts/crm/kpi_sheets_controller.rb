class Api::V1::Accounts::Crm::KpiSheetsController < Api::V1::Accounts::Crm::BaseController
  # 绩效审批链参与者可能不是 CRM 销售（人事/总经理）。放宽门禁：
  # CRM 成员（管理员/主管/业务员）或被指定的人事/总经理均可进。
  skip_before_action :ensure_crm_access
  before_action :ensure_kpi_access
  before_action :check_authorization
  before_action :fetch_sheet, only: [:show, :update, :destroy, :submit, :score, :hr_confirm, :gm_confirm, :ai_suggest, :return_sheet]

  # 数据范围：超管/管理员/指定人事/总经理看全部；部门负责人看本部门（含下级）+ 自己；业务员只看自己。
  # 财务额外看全员「已归档」表（发放绩效薪资用），叠加在自身可见范围上。
  def index
    scope = Current.account.crm_kpi_sheets.includes(:owner, :sheet_items)
    unless all_sheets_visible?
      ids = visible_sheet_owner_ids
      scope = if Current.account_user&.crm_finance?
                scope.where('crm_kpi_sheets.owner_id IN (:ids) OR crm_kpi_sheets.status = :st', ids: ids, st: 'ARCHIVED')
              else
                scope.where(owner_id: ids)
              end
    end
    scope = scope.for_month(Date.parse(params[:month])) if params[:month].present?
    @sheets = scope.order(period_month: :desc, id: :desc)
  end

  # 财务批量发放：把选中的「已归档」绩效表标记为已发放（金额=系统已算的 actual_payout_micros）。
  def mark_paid
    return unless ensure_finance!

    sheets = Current.account.crm_kpi_sheets.where(id: Array(params[:ids]), status: 'ARCHIVED').to_a
    sheets.each { |s| s.mark_paid!(by: current_user) }
    render json: { count: sheets.size }
  end

  # 财务撤销发放（点错兜底）。
  def unmark_paid
    return unless ensure_finance!

    Current.account.crm_kpi_sheets.where(id: Array(params[:ids])).find_each(&:unmark_paid!)
    head :ok
  end

  def show; end

  # 保存完成值(员工)/得分(主管)。按行 id 更新。备注/补充条款仅主管·管理员可改。
  def update
    Array(params.dig(:sheet, :sheet_items)).each do |raw|
      item = @sheet.sheet_items.find_by(id: raw[:id])
      next unless item

      attrs = raw.permit(:actual_value, :score).to_h
      item.update!(attrs) if attrs.present?
    end
    @sheet.update!(remark: params.dig(:sheet, :remark)) if can_manage? && params[:sheet]&.key?(:remark)
    @sheet.reload
    render 'show'
  end

  # 撤回下发：把整张考核表删掉（发错人/发错月/方案发早了）。仅「待填报」阶段可撤回，避免误删已填数据。
  def destroy
    return unless ensure_can_recall!

    @sheet.destroy!
    head :ok
  end

  # ── 审批链（每步：上传本方电子签 + 状态流转）。守卫失败即渲染错误并中断 ──
  def submit
    return unless ensure_owner!
    return unless ensure_before_deadline!
    return unless ensure_signature!
    return unless transition!('PENDING', 'SUBMITTED') do
      attach_signature(:employee_signature)
      @sheet.employee_signed_at = Time.current
      # 重新提交则清掉上次退回痕迹
      @sheet.assign_attributes(return_reason: nil, returned_at: nil, returned_by_id: nil)
    end

    render 'show'
  end

  # 退回重填：审批人在自己那一步发现问题，退回到「待填报」，须填原因；员工改完重走流程。
  def return_sheet
    return unless ensure_can_return!

    reason = params[:reason].to_s.strip
    return render_error('请填写退回原因', :unprocessable_entity) if reason.blank?

    @sheet.reset_for_return!(reason: reason, by: current_user)
    render 'show'
  end

  # 退回主管改分：已交人事（SCORED）时，人事或主管发现主管打错分，退回到「待打分」；
  # 员工填报/签名不动，主管改完分重新提交。原因选填。
  def reopen_scoring
    return unless ensure_can_reopen_scoring!

    @sheet.reopen_scoring!(reason: params[:reason].to_s.strip, by: current_user)
    render 'show'
  end

  def score
    return unless ensure_manager!
    return unless ensure_signature!
    return unless transition!('SUBMITTED', 'SCORED') do
      attach_signature(:manager_signature)
      @sheet.manager_id = current_user.id
      @sheet.manager_signed_at = Time.current
      # 主管改完分重新提交则清掉「退回主管改分」痕迹
      @sheet.assign_attributes(return_reason: nil, returned_at: nil, returned_by_id: nil)
    end

    @sheet.recompute_payout!
    render 'show'
  end

  def hr_confirm
    return unless ensure_role!(:hr_owner_id)
    return unless ensure_signature!
    return unless transition!('SCORED', 'HR_CONFIRMED') do
      attach_signature(:hr_signature)
      @sheet.hr_id = current_user.id
      @sheet.hr_confirmed_at = Time.current
    end

    render 'show'
  end

  def gm_confirm
    return unless ensure_role!(:gm_owner_id)
    return unless ensure_signature!
    return unless transition!('HR_CONFIRMED', 'ARCHIVED') do
      attach_signature(:gm_signature)
      @sheet.gm_id = current_user.id
      @sheet.gm_confirmed_at = Time.current
    end

    render 'show'
  end

  # AI 打分建议：为各指标算建议分（存入 suggested_score），理由随本次响应返回供主管参考。
  # 仅打分权限者可用；最终分仍由主管手填，AI 只作参考。
  def ai_suggest
    return unless ensure_manager!

    rows = @sheet.sheet_items.ordered.to_a
    render json: { suggestions: apply_ai_suggestions(rows, ai_score_suggestions(rows)) }
  rescue Crm::EmailAiService::NotConfigured => e
    render_error(e.message, :unprocessable_entity)
  rescue RubyLLM::Error, Faraday::Error
    render_error('AI 服务暂时不可用，请稍后再试', :bad_gateway)
  end

  private

  # 业绩类指标（CRM_SALES）按公式硬算建议分 = 完成 ÷ 保底 × 权重（保底取薪资配置），其余指标交 AI 参考。
  # 返回 [{ 'i', 'score', 'reason' }, ...]，'i' 为在 rows 中的原始序号。
  def ai_score_suggestions(rows)
    indexed = rows.each_with_index.to_a
    formula_rows, ai_rows = indexed.partition { |item, _| item.data_source == 'CRM_SALES' && perf_baseline_micros.to_i.positive? }

    results = formula_rows.map { |item, idx| formula_perf_suggestion(item, idx) }
    results.concat(ai_suggestions_for(ai_rows)) if ai_rows.any?
    results
  end

  # 调 AI 给非业绩指标打建议分；AI 返回的 'i' 是它收到列表内的位置，需映射回 rows 原始序号。
  def ai_suggestions_for(ai_rows)
    hints = Crm::EmailAiService.new(account: Current.account).score_suggestions(
      pass_score: @sheet.pass_score,
      cap_pct: @sheet.item_score_cap_pct,
      items: ai_rows.map do |item, _|
        { name: item.name, dimension: item.dimension, weight: item.weight, standard: item.standard,
          target: item.target_value, baseline: item.baseline_value, actual: item.actual_value }
      end
    )
    hints.filter_map do |h|
      orig_idx = ai_rows[h['i'].to_i]&.last
      { 'i' => orig_idx, 'score' => h['score'], 'reason' => h['reason'] } if orig_idx
    end
  end

  # 业绩建议分：完成 ÷ 保底 × 权重，按单项上限封顶（未设上限则允许溢出）。完成值未填按 0 分。
  def formula_perf_suggestion(item, idx)
    baseline_yuan = perf_baseline_micros.to_f / 1_000_000
    weight = item.weight.to_f
    cap = @sheet.item_score_cap_pct ? (@sheet.item_score_cap_pct.to_f / 100) : Float::INFINITY
    actual_yuan = parse_amount_yuan(item.actual_value)

    if actual_yuan.nil?
      return { 'i' => idx, 'score' => 0, 'reason' => "完成值未填，暂给 0 分（保底 #{fmt_wan(baseline_yuan)}）" }
    end

    ratio = actual_yuan / baseline_yuan
    score = [ratio * weight, weight * cap].min.round(1)
    { 'i' => idx, 'score' => score,
      'reason' => "完成 #{fmt_wan(actual_yuan)} ÷ 保底 #{fmt_wan(baseline_yuan)} = #{(ratio * 100).round}%，×权重 #{weight.round(1)} = #{score} 分" }
  end

  # 保底目标（micros）：优先考核表下发时的快照，为空则回退读该业务员当前薪资配置（治「配置晚于下发」的空值）。
  def perf_baseline_micros
    return @perf_baseline_micros if defined?(@perf_baseline_micros)

    @perf_baseline_micros = @sheet.baseline_target_micros.presence ||
                            Current.account.crm_employee_comps.owned_by(@sheet.owner_id)
                                   .order(created_at: :desc).first&.baseline_target_micros
  end

  # 把业务员手填的完成值文本解析成「元」数值：去掉千分位/货币符号，识别「万」单位；纯数字按元计。
  def parse_amount_yuan(str)
    cleaned = str.to_s.gsub(/[,，\s¥￥元]/, '')
    num = cleaned[/-?\d+(\.\d+)?/]
    return nil if num.blank?

    cleaned.include?('万') ? num.to_f * 10_000 : num.to_f
  end

  def fmt_wan(yuan)
    "#{(yuan / 10_000.0).round(2)}万"
  end

  # 按序号回填建议分并存库，返回带理由的列表（理由不入库，仅本次响应展示）。
  def apply_ai_suggestions(rows, suggestions)
    rows.each_with_index.filter_map do |item, idx|
      hint = suggestions.find { |s| s['i'] == idx }
      next unless hint && hint['score']

      item.update!(suggested_score: hint['score'])
      { id: item.id, suggested_score: item.suggested_score, reason: hint['reason'] }
    end
  end

  def fetch_sheet
    @sheet = Current.account.crm_kpi_sheets.includes(:sheet_items, :owner).find(params[:id])
  end

  def check_authorization
    authorize(Crm::KpiSheet)
  end

  # 考核表按角色可见性放行（管理员/被指定人事·总经理/或开关允许的主管·业务员）。
  def ensure_kpi_access
    return if Crm::PerformanceSetting.sheet_visible?(Current.account.crm_performance_setting, Current.account_user)

    render_error(I18n.t('errors.crm.no_access', default: '无权访问 CRM'), :forbidden)
  end

  def can_manage?
    au = Current.account_user
    return false unless au

    au.administrator? || au.crm_deputy_admin? || au.crm_hr? || au.crm_manager?
  end

  # 全量可见：超管/管理员，以及被指定的人事/总经理（审批链需要）。
  def all_sheets_visible?
    au = Current.account_user
    return false unless au
    return true if au.administrator? || au.crm_deputy_admin? || au.crm_hr?

    [perf_setting.hr_owner_id, perf_setting.gm_owner_id].include?(current_user.id)
  end

  # 部门负责人=所辖部门（含下级）成员 + 自己；业务员/其他=仅自己。
  def visible_sheet_owner_ids
    return [current_user.id] unless Current.account_user&.crm_manager?

    led = Current.account.org_departments.where(leader_id: current_user.id).pluck(:id)
    return [current_user.id] if led.empty?

    dept_ids = Org::Department.subtree_ids(Current.account, led)
    (Current.account.org_memberships.where(department_id: dept_ids).pluck(:user_id) + [current_user.id]).uniq
  end

  def perf_setting
    @perf_setting ||= Crm::PerformanceSetting.for_account(Current.account)
  end

  # 状态匹配则执行 yield+流转并返回 true；否则渲染错误并返回 false。
  def transition!(from, to)
    unless @sheet.status == from
      render_error('状态不符', :unprocessable_entity)
      return false
    end

    yield
    @sheet.status = to
    @sheet.save!
    true
  end

  # 盖章：本次显式上传的签名优先；否则取签字人存的个人签名一键盖上。
  def attach_signature(field)
    if params[:signature].present?
      @sheet.public_send(field).attach(params[:signature])
    elsif my_signature&.image&.attached?
      @sheet.public_send(field).attach(my_signature.image.blob)
    end
  end

  # 必签守卫：本次未传签名且没存个人签名时，拦下并提示去设置。
  def ensure_signature!
    return true if params[:signature].present? || my_signature&.image&.attached?

    render_error('请先在头像菜单「我的签名」里设置个人签名，再签字', :unprocessable_entity)
    false
  end

  def my_signature
    @my_signature ||= Current.account.crm_signatures.find_by(user_id: current_user.id)
  end

  # 守卫：仅被考核本人可提交（管理员/人事不代交）。
  def ensure_owner!
    return true if @sheet.owner_id == current_user.id

    render_error('仅被考核本人可提交', :forbidden)
    false
  end

  # 提交截止：须在考核月「次月」的第 N 天前提交，逾期任何人都不能再提交（管理员/人事也不代交）。
  def ensure_before_deadline!
    day = perf_setting.submit_deadline_day
    return true if day.blank?

    deadline = @sheet.period_month.to_date.next_month.change(day: day).end_of_day
    return true if Time.zone.now <= deadline

    render_error("提交已截止（截止 #{deadline.strftime('%-m月%-d日')}），逾期无法提交", :unprocessable_entity)
    false
  end

  # 撤回权限：仅「待填报」可撤回（已提交请用退回重填）；管理员/副管理员撤任意，主管仅限本部门（含下级）。
  def ensure_can_recall!
    unless @sheet.status == 'PENDING'
      render_error('该考核表已提交，不能撤回；如需修改请用「退回重填」', :unprocessable_entity)
      return false
    end

    au = Current.account_user
    return true if au&.administrator? || au&.crm_deputy_admin? || au&.crm_hr?
    return true if au&.crm_manager? && visible_sheet_owner_ids.include?(@sheet.owner_id)

    render_error('你无权撤回这张考核表', :forbidden)
    false
  end

  # 退回权限：当前状态下的审批人（主管/人事/总经理）或管理员可退回；已归档/待填报不可退。
  def ensure_can_return!
    admin = Current.account_user&.administrator?
    allowed = { 'SUBMITTED' => can_manage?,
                'SCORED' => admin || current_user.id == perf_setting.hr_owner_id,
                'HR_CONFIRMED' => admin || current_user.id == perf_setting.gm_owner_id }[@sheet.status]
    return true if allowed

    render_error('当前状态下你无权退回', :forbidden)
    false
  end

  # 退回主管改分权限：仅「待人事确认/待总经理确认」可退；主管、人事、总经理或管理员均可触发。
  def ensure_can_reopen_scoring!
    unless %w[SCORED HR_CONFIRMED].include?(@sheet.status)
      render_error('仅待人事/总经理确认的表可退回主管改分', :unprocessable_entity)
      return false
    end

    allowed = can_manage? ||
              [perf_setting.hr_owner_id, perf_setting.gm_owner_id].include?(current_user.id)
    return true if allowed

    render_error('你无权退回此表', :forbidden)
    false
  end

  def ensure_manager!
    return true if can_manage?

    render_error('仅主管/管理员可打分', :forbidden)
    false
  end

  def ensure_finance!
    return true if Current.account_user&.crm_finance?

    render_error('仅财务可操作发放', :forbidden)
    false
  end

  # 指定审批人（人事/总经理）或系统管理员。
  def ensure_role!(field)
    designated = perf_setting.public_send(field)
    return true if current_user.id == designated || Current.account_user&.administrator?

    render_error('无权确认此步', :forbidden)
    false
  end

  def render_error(msg, status)
    render json: { error: msg }, status: status
  end
end
