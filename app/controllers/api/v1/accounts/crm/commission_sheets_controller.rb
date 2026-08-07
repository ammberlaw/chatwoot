class Api::V1::Accounts::Crm::CommissionSheetsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_sheet, only: [:show, :update, :destroy, :pull_orders, :submit, :approve, :return_sheet, :xlsx]

  # 列表：业务员看自己；主管（部门负责人）看本部门（含下级）+ 自己；财务额外看全员「已通过」；管理员/副管看全部。
  def index
    scope = Current.account.crm_commission_sheets.includes(:owner, :manager, :returned_by, :items)
    scope = scope.for_month(Date.parse(params[:month])) if params[:month].present?
    ids = crm_visible_owner_ids
    unless ids == :all
      scope = if Current.account_user&.crm_finance?
                scope.where('crm_commission_sheets.owner_id IN (:ids) OR crm_commission_sheets.status = :st',
                            ids: ids, st: 'APPROVED')
              else
                scope.where(owner_id: ids)
              end
    end
    @sheets = scope.order(period_month: :desc, id: :desc)
  end

  def show; end

  # 建表：一人一月一张。已存在则直接返回（不重复建），新建时自动带出本月订单明细。
  def create
    month = Date.parse(params[:month]).beginning_of_month
    owner_id = resolve_owner_id
    return render_error('无权为该成员建表', :forbidden) if owner_id != current_user.id && !admin_like?

    @sheet = Current.account.crm_commission_sheets.find_by(owner_id: owner_id, period_month: month)
    if @sheet
      render :show
      return
    end

    @sheet = Current.account.crm_commission_sheets.create!(owner_id: owner_id, period_month: month, status: 'DRAFT')
    build_items_from_orders(@sheet)
    @sheet.reload
    render :show
  end

  # 保存明细行 + 备注。仅草稿/退回态且有编辑权（本人或管理员）可改。
  def update
    return render_error('该提成表当前状态不可编辑', :unprocessable_entity) unless @sheet.editable?
    return render_error('无权编辑该提成表', :forbidden) unless can_edit?(@sheet)

    @sheet.update!(sheet_params)
    @sheet.reload
    render :show
  end

  def destroy
    return render_error('已提交/已通过的表不能删除', :unprocessable_entity) unless @sheet.editable?
    return render_error('无权删除该提成表', :forbidden) unless can_edit?(@sheet)

    @sheet.destroy!
    head :ok
  end

  # 重新带出：把本月新增、尚未在表里的订单补进来（业务员开始填后又来了新单时用）。
  def pull_orders
    return render_error('该提成表当前状态不可编辑', :unprocessable_entity) unless @sheet.editable?
    return render_error('无权编辑该提成表', :forbidden) unless can_edit?(@sheet)

    before = @sheet.items.count
    build_items_from_orders(@sheet)
    @sheet.reload
    @added = @sheet.items.count - before
    render :show
  end

  # 提交审批（业务员本人 / 管理员）。
  def submit
    return render_error('无权提交该提成表', :forbidden) unless @sheet.owner_id == current_user.id || admin_like?
    return render_error('仅草稿/退回状态可提交', :unprocessable_entity) unless @sheet.editable?

    @sheet.submit!
    render :show
  end

  # 主管通过。
  def approve
    return render_error('无权审批该提成表', :forbidden) unless can_approve?(@sheet)
    return render_error('仅「已提交」的表可通过', :unprocessable_entity) unless @sheet.status == 'SUBMITTED'

    @sheet.approve!(by: current_user)
    render :show
  end

  # 主管退回（须填原因）。
  def return_sheet
    return render_error('无权退回该提成表', :forbidden) unless can_approve?(@sheet)
    return render_error('仅「已提交」的表可退回', :unprocessable_entity) unless @sheet.status == 'SUBMITTED'

    reason = params[:reason].to_s.strip
    return render_error('请填写退回原因', :unprocessable_entity) if reason.blank?

    @sheet.return!(reason: reason, by: current_user)
    render :show
  end

  # 导出 xlsx（优化版式：按产品品类分组小计 + 总计）。
  def xlsx
    return render_error('无权导出该提成表', :forbidden) unless can_view?(@sheet)

    stream = Crm::CommissionXlsxService.new(@sheet).to_stream
    send_data stream.read,
              filename: "提成表-#{sheet_label(@sheet)}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  private

  def fetch_sheet
    @sheet = Current.account.crm_commission_sheets.includes(:items, :owner, :manager, :returned_by).find(params[:id])
  end

  def check_authorization
    authorize(Crm::CommissionSheet)
  end

  # 建表归属人：默认自己；管理员/主管可显式为下属建。
  def resolve_owner_id
    params[:owner_id].presence&.to_i || current_user.id
  end

  # 从该业务员当月的（未取消）销售订单带出明细，跳过已在表里的订单。
  def build_items_from_orders(sheet)
    existing = sheet.items.where.not(crm_sales_order_id: nil).pluck(:crm_sales_order_id)
    orders = Current.account.crm_sales_orders.owned_by(sheet.owner_id).dealt
                    .where(order_date: sheet.period_month.beginning_of_month..sheet.period_month.end_of_month)
                    .where.not(id: existing)
                    .includes(:crm_customer)
                    .order(:order_date, :id)
    pos = sheet.items.maximum(:position).to_i
    orders.each do |o|
      pos += 1
      sheet.items.create!(
        position: pos, crm_sales_order_id: o.id,
        customer_name: o.crm_customer&.name, country: o.crm_customer&.trade_country,
        order_no: o.pi_no.presence || o.order_no,
        order_amount_micros: o.order_amount_micros, currency: o.order_currency,
        exchange_rate: o.exchange_rate, product: product_summary(o.line_items)
      )
    end
  end

  # 产品列摘要：把订单明细拼成「数量×名称，…」。
  def product_summary(line_items)
    return nil unless line_items.is_a?(Array)

    line_items.filter_map do |li|
      name = li['name'].to_s.strip
      next if name.blank?

      qty = li['quantity']
      qty.present? ? "#{qty}×#{name}" : name
    end.join('，').presence
  end

  def admin_like?
    au = Current.account_user
    au&.administrator? || au&.crm_deputy_admin? || false
  end

  # 编辑权：本人或管理员/副管。
  def can_edit?(sheet)
    admin_like? || sheet.owner_id == current_user.id
  end

  # 审批权：管理员/副管；或主管对本团队成员（不含自己——自己的表由更高层批）。
  def can_approve?(sheet)
    return true if admin_like?
    return false unless Current.account_user&.crm_manager? && sheet.owner_id != current_user.id

    ids = crm_visible_owner_ids
    ids != :all && Array(ids).include?(sheet.owner_id)
  end

  # 查看/导出权：管理员；本人；财务看已通过；主管看本团队。
  def can_view?(sheet)
    return true if admin_like? || sheet.owner_id == current_user.id
    return true if Current.account_user&.crm_finance? && sheet.status == 'APPROVED'

    ids = crm_visible_owner_ids
    ids != :all && Array(ids).include?(sheet.owner_id)
  end

  def sheet_label(sheet)
    "#{sheet.owner&.crm_display_name}-#{sheet.period_month.strftime('%Y年%-m月')}"
  end

  def sheet_params
    params.require(:sheet).permit(
      :remark,
      items_attributes: [
        :id, :position, :product_category, :country, :customer_name, :order_no, :crm_sales_order_id,
        :order_amount_micros, :currency, :shipping_micros, :received_amount_micros, :exchange_rate,
        :received_rmb_micros, :sales_rmb_micros, :payment_channel, :payment_date, :product, :remark, :_destroy
      ]
    )
  end

  def render_error(msg, status)
    render json: { error: msg }, status: status
  end
end
