class Api::V1::Accounts::Crm::SalesOrdersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_sales_order, only: [:show, :update, :destroy, :attach, :detach, :audits]

  RESULTS_PER_PAGE = 15

  def index
    @sales_orders_scope = filtered_sales_orders
    @sales_orders_count = @sales_orders_scope.count
    @sales_orders = @sales_orders_scope
                    .order(order_date: :desc)
                    .page(permitted_params[:page] || 1)
                    .per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    attrs = order_attributes
    @sales_order = Current.account.crm_sales_orders.create!(attrs.merge(owner_id: attrs[:owner_id] || current_user.id))
  end

  def update
    @sales_order.update!(order_attributes)
  end

  # 读取 PI 自动识别：上传 PDF/Excel，返回字段化结果供前端校对（不落库）。
  def parse_pi
    return render json: { error: '请上传 PI 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Crm::PiParseService.new(account: Current.account, user: current_user, file: params[:file]).call
    render json: result
  rescue Crm::PiParseService::UnsupportedType, Crm::EmailAiService::NotConfigured => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PI parse] #{e.class}: #{e.message}")
    render json: { error: 'PI 识别失败，请检查文件或稍后重试' }, status: :unprocessable_entity
  end

  def destroy
    @sales_order.destroy!
    head :ok
  end

  def attach
    @sales_order.files.attach(params[:files])
    render 'api/v1/accounts/crm/sales_orders/show'
  end

  def detach
    @sales_order.files.find(params[:attachment_id]).purge
    render 'api/v1/accounts/crm/sales_orders/show'
  end

  # 操作历史：订单的创建/编辑记录。
  def audits
    rows = @sales_order.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.crm_display_name || audit.username || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
  end

  private

  def fetch_sales_order
    @sales_order = Current.account.crm_sales_orders.find(params[:id])
  end

  def check_authorization
    authorize(Crm::SalesOrder)
  end

  # 视图筛选：我的订单、未关联客户（数据兜底）、按状态（生产中…）、按客户。
  # 基础可见范围按部门授权（管理员全部/主管本部门及下级/业务员自己）。
  def filtered_sales_orders
    scope = visible_sales_orders
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: nil) if params[:filter] == 'no_customer'
    apply_order_filters(scope)
  end

  ORDER_COLUMN_FILTERS = { status: :status, customer_id: :crm_customer_id, owner_id: :owner_id }.freeze

  def apply_order_filters(scope)
    ORDER_COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = by_month(scope, params[:month]) if params[:month].present?
    scope = search(scope, params[:q]) if params[:q].present?
    scope
  end

  def visible_sales_orders
    scope_by_owner(Current.account.crm_sales_orders)
  end

  # 按下单月份筛选（month 形如 2026-07）；格式非法则忽略。
  def by_month(scope, month)
    start = Date.strptime(month, '%Y-%m').beginning_of_month
    scope.where(order_date: start.beginning_of_day..start.end_of_month.end_of_day)
  rescue ArgumentError
    scope
  end

  # 搜索：订单号 / 订单名称 / 关联客户名（左连避免漏掉未关联客户的订单）。
  def search(scope, query)
    term = "%#{query.strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_sales_orders.order_no ILIKE :t OR crm_sales_orders.name ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  def sales_order_params
    params.require(:sales_order).permit(
      :name, :order_no, :pi_no, :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :status, :order_date, :delivery_date, :order_currency, :exchange_rate,
      :order_amount_micros, :cost_amount_micros, :profit_amount_micros, :profit_rate, :remark,
      :line_items_json,
      files: []
    )
  end

  # 明细以 JSON 字符串传入（multipart 建单无法带嵌套数组），这里解析成 line_items 数组存 jsonb。
  def order_attributes
    attrs = sales_order_params.to_h.symbolize_keys
    json = attrs.delete(:line_items_json)
    attrs[:line_items] = parse_line_items(json) unless json.nil?
    attrs
  end

  def parse_line_items(json)
    items = JSON.parse(json.to_s)
    return [] unless items.is_a?(Array)

    items.filter_map do |item|
      next unless item.is_a?(Hash)

      name = item['name'].to_s.strip
      next if name.blank?

      {
        'name' => name,
        'spec' => item['spec'].to_s.strip,
        'quantity' => item['quantity'],
        'unit_price' => item['unit_price'],
        'amount' => item['amount']
      }
    end
  rescue JSON::ParserError
    []
  end

  def permitted_params
    params.permit(:page, :filter, :status, :customer_id, :q, :owner_id, :month)
  end
end
