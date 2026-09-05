class Api::V1::Accounts::Crm::CommissionSheetsController < Api::V1::Accounts::Crm::BaseController
  # 财务身份（crm_finance）常无 crm_role，会被 CRM 总门禁 can_access_crm? 拦掉。
  # 与考核表/员工提成同款：跳过总门禁，数据范围与写权限已在本控制器按角色/审批链把关
  #（财务只看全员「已通过」+ 导出 + 发放，改/审/提交/删均被 can_edit?/can_approve? 挡住）。
  skip_before_action :ensure_crm_access
  before_action :check_authorization
  before_action :fetch_sheet, only: [:show, :update, :destroy, :pull_orders, :submit, :approve, :return_sheet, :xlsx,
                                     :selectable_orders, :import_orders]

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

  # 建表：一人一月一张。已存在则直接返回（不重复建）。
  # 新建即空白表——订单一律由业务员用「选单导入」按月手动选进来，
  # 避免自动带单把别月已填的订单又带过来（提成一单只进一张表）。
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
    render :show
  rescue ActiveRecord::RecordNotUnique
    # 并发/双击：另一个请求已建同月表，幂等返回既有表，不再 500。
    @sheet = Current.account.crm_commission_sheets.find_by!(owner_id: owner_id, period_month: month)
    render :show
  end

  # 保存明细行 + 备注。业务员本人/管理员/副管：仅草稿/退回态可改。
  # 财务(crm_finance)：可对任意状态（含已通过）全字段编辑，用于复核阶段补汇率等。
  def update
    finance = Current.account_user&.crm_finance?
    return render_error('该提成表当前状态不可编辑', :unprocessable_entity) unless @sheet.editable? || finance
    return render_error('无权编辑该提成表', :forbidden) unless can_edit?(@sheet) || finance
    # 已发放的提成表任何人不可再改（含财务），防已发放金额被静默篡改。
    return render_error('该提成表已发放，不能再编辑', :unprocessable_entity) if @sheet.paid?

    @sheet.with_lock do
      raise ActiveRecord::Rollback if @sheet.paid? # 锁内复检，防与发放并发

      @sheet.update!(sheet_params)
    end
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

  # 选单导入：列出该业务员「已完成 + 尚未在本表」的销售订单，供前端勾选。
  # 提成只认已完成订单（发货月口径），未完成的不出现在可选列表。
  def selectable_orders
    return render_error('无权编辑该提成表', :forbidden) unless can_edit?(@sheet)

    orders = Current.account.crm_sales_orders.owned_by(@sheet.owner_id).completed
                    .where.not(id: imported_order_ids(@sheet))
                    .includes(:crm_customer)
                    .order(order_date: :desc, id: :desc).limit(500)
    render json: {
      orders: orders.map do |o|
        {
          id: o.id, order_no: o.pi_no.presence || o.order_no,
          customer_name: o.crm_customer&.name, country: o.crm_customer&.trade_country,
          amount_micros: o.order_amount_micros, currency: o.order_currency,
          order_date: o.order_date
        }
      end
    }
  end

  # 导入选中的销售订单为明细行（仅草稿/退回态、有编辑权）。
  def import_orders
    return render_error('该提成表当前状态不可编辑', :unprocessable_entity) unless @sheet.editable?
    return render_error('无权编辑该提成表', :forbidden) unless can_edit?(@sheet)

    ids = Array(params[:order_ids]).map(&:to_i)
    orders = Current.account.crm_sales_orders.owned_by(@sheet.owner_id).completed
                    .where(id: ids).where.not(id: imported_order_ids(@sheet))
                    .includes(:crm_customer).order(:order_date, :id)
    before = @sheet.items.count
    append_items_from_orders(@sheet, orders, category: params[:product_category].to_s.strip.presence)
    @sheet.reload
    @added = @sheet.items.count - before
    render :show
  end

  # 提交审批（业务员本人 / 管理员）。
  def submit
    return render_error('无权提交该提成表', :forbidden) unless @sheet.owner_id == current_user.id || admin_like?

    ok = @sheet.with_lock { @sheet.editable? && @sheet.submit! }
    return render_error('仅草稿/退回状态可提交', :unprocessable_entity) unless ok
    crm_notify_managers_of(@sheet.owner_id,
                           "【提成表】#{@sheet.owner&.name} 提交了 #{month_label(@sheet.period_month)} 提成表，请及时审批。")
    render :show
  end

  # 主管通过。
  def approve
    return render_error('无权审批该提成表', :forbidden) unless can_approve?(@sheet)

    ok = @sheet.with_lock { @sheet.status == 'SUBMITTED' && @sheet.approve!(by: current_user) }
    return render_error('仅「已提交」的表可通过', :unprocessable_entity) unless ok
    crm_notify(@sheet.owner_id, "【提成表】你的 #{month_label(@sheet.period_month)} 提成表已通过审批。")
    render :show
  end

  # 退回（须填原因）：主管退回「已提交」待审的；财务退回「已通过但未发放」的
  # （核算发现有误，打回业务员重填，之后重走 提交→审批→发放）。已发放的须先撤销发放再退回。
  def return_sheet
    reason = params[:reason].to_s.strip
    return render_error('请填写退回原因', :unprocessable_entity) if reason.blank?
    return render_error('无权退回该提成表', :forbidden) unless can_return?(@sheet)
    return render_error('该表已发放，请先撤销发放再退回', :unprocessable_entity) if @sheet.paid?

    from = @sheet.status
    ok = @sheet.with_lock do
      next false if @sheet.paid?
      next false unless can_return?(@sheet)

      @sheet.return!(reason: reason, by: current_user)
    end
    return render_error('该表当前状态不可退回', :unprocessable_entity) unless ok
    by_label = from == 'APPROVED' ? '财务' : '主管'
    crm_notify(@sheet.owner_id,
               "【提成表】你的 #{month_label(@sheet.period_month)} 提成表被#{by_label}退回，原因：#{reason}，请修改后重新提交。")
    render :show
  end

  # 财务批量发放：把选中的「已通过」提成表标记为已发放，逐张带实发金额/备注。
  # 入参 items: [{ id, paid_amount_micros, paid_note }]；单张发放亦走此接口（items 长度 1）。
  def mark_paid
    return unless ensure_finance!

    rows = Array(params[:items]).index_by { |r| r[:id].to_i }
    # 只发「已通过且未发放」的表；每张锁内复检,杜绝并发/重试重复发放覆盖。
    paid = 0
    Current.account.crm_commission_sheets
           .where(id: rows.keys, status: 'APPROVED', paid_at: nil).find_each do |s|
      s.with_lock do
        next if s.paid?

        r = rows[s.id]
        s.mark_paid!(by: current_user,
                     amount_micros: r[:paid_amount_micros].presence&.to_i,
                     note: r[:paid_note].to_s.strip)
        paid += 1
      end
    end
    render json: { count: paid }
  end

  # 财务撤销发放（点错兜底）：仅撤销确实已发放的表。
  def unmark_paid
    return unless ensure_finance!

    Current.account.crm_commission_sheets
           .where(id: Array(params[:ids])).where.not(paid_at: nil).find_each(&:unmark_paid!)
    head :ok
  end

  # 导出 xlsx（优化版式：按产品品类分组小计 + 总计）。
  def xlsx
    return render_error('无权导出该提成表', :forbidden) unless can_view?(@sheet)

    stream = Crm::CommissionXlsxService.new(@sheet).to_stream
    send_data stream.read,
              filename: "提成表-#{sheet_label(@sheet)}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 提成点配置（品类→点位%）：列出。所有能进提成表的人可读（渲染详情要用）。
  def rates
    render json: { rates: rate_rows }
  end

  # 批量保存提成点（管理员/副管/财务）。整表覆盖式保存，品类去重。
  def save_rates
    return render_error('无权配置提成点', :forbidden) unless can_manage_rates?

    # delete_all 后再用关联 create! 会丢 account_id（Rails 关联代理坑），改显式传 account_id。
    # 强制用当前账号 id（忽略请求参数），防越权清空/覆盖他账号的提成点配置。
    aid = Current.account.id
    Crm::CommissionRate.transaction do
      Crm::CommissionRate.where(account_id: aid).delete_all
      Array(params[:rates]).each_with_object({}) do |r, seen|
        category = r[:product_category].to_s.strip
        next if category.blank? || seen[category]

        seen[category] = true
        Crm::CommissionRate.create!(account_id: aid, product_category: category,
                                    rate: r[:rate].to_f.clamp(0, 100))
      end
    end
    render json: { rates: rate_rows }
  end

  private

  # 通知文案里的月份标签，如「2026年8月」。
  def month_label(date)
    date.blank? ? '' : "#{date.year}年#{date.month}月"
  end

  def rate_rows
    Crm::CommissionRate.where(account_id: Current.account.id).order(:product_category)
                       .map { |r| { product_category: r.product_category, rate: r.rate.to_f } }
  end

  def can_manage_rates?
    admin_like? || Current.account_user&.crm_finance?
  end

  def fetch_sheet
    @sheet = Current.account.crm_commission_sheets
                    .includes(:owner, :manager, :returned_by, items: :sales_order).find(params[:id])
  end

  def check_authorization
    authorize(Crm::CommissionSheet)
  end

  # 建表归属人：默认自己；管理员/主管可显式为下属建。
  def resolve_owner_id
    params[:owner_id].presence&.to_i || current_user.id
  end

  # 带出该业务员「已完成」且尚未在任何表里的销售订单为明细。
  # 归月口径：订单完成后第一次拉单即落入当月表，不再按下单日期归月。
  def build_items_from_orders(sheet)
    orders = Current.account.crm_sales_orders.owned_by(sheet.owner_id).completed
                    .where.not(id: imported_order_ids(sheet))
                    .includes(:crm_customer)
                    .order(:order_date, :id)
    append_items_from_orders(sheet, orders)
  end

  # 把一批销售订单追加为明细行（跳过已导入的），复用建表与选单导入。
  # category 传入时给这批行统一设产品品类（选单导入指定；自动建表不传）。
  def append_items_from_orders(sheet, orders, category: nil)
    pos = sheet.items.maximum(:position).to_i
    orders.each do |o|
      pos += 1
      attrs = item_attrs_from_order(o, sheet.period_month).merge(position: pos)
      attrs[:product_category] = category if category.present?
      begin
        sheet.items.create!(attrs)
      rescue ActiveRecord::RecordNotUnique
        pos -= 1 # 该订单已被导入(并发/已在别的表)，唯一约束拦下，跳过防重复计提成
      end
    end
  end

  # 提成基数折算按「本月第一天」中行现汇买入价（无牌价往后顺延）；CNY 恒 1。
  # 订单金额=净销售(不含运费)，收款额=订单金额+运费。带单自动带出运费/收款额/两个RMB列：
  #   销售额RMB = 净销售 × 汇率（进提成基数），收款额RMB = 收款额 × 汇率。
  # 抓不到汇率则 RMB 列留空由业务员手填；CNY 单汇率列留空但 RMB 仍按面值带出。
  def item_attrs_from_order(order, period_month)
    cny = order.order_currency.blank? || order.order_currency == 'CNY'
    rate = Crm::FxRate.rate_on_or_after(order.order_currency, period_month.beginning_of_month)
    net = order.order_amount_micros
    received = net ? net.to_i + order.shipping_micros.to_i : nil
    {
      crm_sales_order_id: order.id,
      customer_name: order.crm_customer&.name, country: order.crm_customer&.trade_country,
      order_no: order.pi_no.presence || order.order_no,
      order_amount_micros: net, currency: order.order_currency,
      shipping_micros: order.shipping_micros, received_amount_micros: received,
      exchange_rate: cny ? nil : rate,
      sales_rmb_micros: rate && net ? (net * rate).round : nil,
      received_rmb_micros: rate && received ? (received * rate).round : nil,
      product: product_summary(order.line_items)
    }
  end

  # 该业务员「所有月份提成表」已导入的订单 id：一单只进一张表，
  # 首次拉单落月后其余月份不再带出（否则新建上月表会把本月已填的单又带过去）。
  def imported_order_ids(sheet)
    owner_sheet_ids = Current.account.crm_commission_sheets.owned_by(sheet.owner_id).select(:id)
    Crm::CommissionItem.where(crm_commission_sheet_id: owner_sheet_ids)
                       .where.not(crm_sales_order_id: nil)
                       .pluck(:crm_sales_order_id)
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

  def ensure_finance!
    return true if Current.account_user&.crm_finance?

    render_error('仅财务可操作发放', :forbidden)
    false
  end

  # 编辑权：本人或管理员/副管。
  def can_edit?(sheet)
    admin_like? || sheet.owner_id == current_user.id
  end

  # 退回权：主管/管理员可退「已提交」待审的；财务/管理员可退「已通过」的（核算发现有误打回重填）。
  def can_return?(sheet)
    case sheet.status
    when 'SUBMITTED' then can_approve?(sheet)
    when 'APPROVED' then admin_like? || Current.account_user&.crm_finance?
    else false
    end
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
        :received_rmb_micros, :sales_rmb_micros, :payment_channel, :payment_date, :product, :remark,
        :is_public_receipt, :tax_rate, :_destroy
      ]
    )
  end

  def render_error(msg, status)
    render json: { error: msg }, status: status
  end
end
