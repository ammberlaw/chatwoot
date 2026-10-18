class Api::V1::Accounts::Mes::StockEntriesController < Api::V1::Accounts::Mes::BaseController
  include Api::V1::Accounts::Mes::DocumentReturnable

  before_action :check_authorization
  before_action :fetch_stock_entry, only: [:show, :update, :destroy, :post, :confirm_warehouse, :cancel, :approve, :reject]
  before_action -> { ensure_owner_or_admin!(@stock_entry, '入库单') }, only: [:update]
  before_action :ensure_can_delete!, only: [:destroy]

  COLUMN_FILTERS = {
    purpose: :purpose, status: :status,
    production_order_id: :production_order_id, purchase_order_id: :purchase_order_id
  }.freeze

  # 表头上每列各自的筛选（对标金蝶的漏斗）。放后端是因为列表分页：
  # 前端只过滤本页，第 2 页往后的命中就全看不见了。
  #
  # 一律走 EXISTS / 子查询，不 join 明细表：入库单一单多行，join 进来单据行会翻倍、
  # 分页数跟着错；而且 mes_stock_entries 和 mes_purchase_orders 上都有 owner_id，
  # join 后外层按 owner 过滤就成了歧义列（生产任务单那边踩过，整页 500）。
  ITEM_MATCH_SQL = lambda { |cond|
    <<~SQL.squish
      EXISTS (SELECT 1 FROM mes_stock_entry_items sei
                LEFT JOIN mes_materials m ON m.id = sei.mes_material_id
                LEFT JOIN crm_products p ON p.id = sei.crm_product_id
               WHERE sei.stock_entry_id = mes_stock_entries.id AND (#{cond}))
    SQL
  }

  # 一个框搜多处：单号 / 采购单号 / 对内备注 / 供应商 / 物料编码 / 品名 / 工单号 / 成品名 / 归属人。
  # 工单号是后补的：一张工单的料摊成十几张单，车间和财务最常用的就是拿工单号来找
  # （原先只按归属人姓名搜生产订单，搜工单号一条都出不来）。内连 users 还会把
  # 没指定归属人的单整个漏掉，一并改成 LEFT JOIN。
  # 表头漏斗是「知道要筛哪一列」时用的，这个框是「只记得一个号或一个厂名」时用的，两者可叠加。
  # ⚠️ 同样全走子查询不 join 明细，理由见 ITEM_MATCH_SQL 上面那段（分页数会翻倍 + owner_id 歧义）。
  SEARCH_SQL = <<~SQL.squish
    mes_stock_entries.entry_no ILIKE :q
    OR mes_stock_entries.purchase_order_id IN (SELECT po.id FROM mes_purchase_orders po
         WHERE po.po_no ILIKE :q OR po.internal_remark ILIKE :q)
    OR mes_stock_entries.purchase_order_id IN (SELECT pit.purchase_order_id FROM mes_purchase_items pit
         JOIN mes_suppliers sup ON sup.id = pit.mes_supplier_id WHERE sup.name ILIKE :q)
    OR mes_stock_entries.production_order_id IN (SELECT mpo.id FROM mes_production_orders mpo
         LEFT JOIN users usr ON usr.id = mpo.owner_id
         WHERE mpo.order_no ILIKE :q OR mpo.product_name ILIKE :q OR usr.name ILIKE :q)
    OR #{ITEM_MATCH_SQL.call('p.sku ILIKE :q OR m.material_no ILIKE :q OR p.name ILIKE :q OR m.name ILIKE :q')}
  SQL

  COLUMN_LIKE_FILTERS = {
    col_no: ->(scope, v) { scope.where('mes_stock_entries.entry_no ILIKE ?', "%#{v}%") },
    col_po: lambda { |scope, v|
      scope.where(purchase_order_id: Mes::PurchaseOrder.where('mes_purchase_orders.po_no ILIKE ?', "%#{v}%").select(:id))
    },
    # 供应商挂在来源采购单的明细行上（一张采购单可能有好几家），入库单自己身上没有这个字段。
    col_supplier: lambda { |scope, v|
      scope.where(purchase_order_id: Mes::PurchaseItem.joins(:mes_supplier)
                                                      .where('mes_suppliers.name ILIKE ?', "%#{v}%")
                                                      .select(:purchase_order_id))
    },
    col_code: ->(scope, v) { scope.where(ITEM_MATCH_SQL.call('p.sku ILIKE :t OR m.material_no ILIKE :t'), t: "%#{v}%") },
    col_name: ->(scope, v) { scope.where(ITEM_MATCH_SQL.call('p.name ILIKE :t OR m.name ILIKE :t'), t: "%#{v}%") },
    col_spec: lambda { |scope, v|
      scope.where(ITEM_MATCH_SQL.call('m.specification ILIKE :t OR p.specification ILIKE :t'), t: "%#{v}%")
    },
    col_owner: lambda { |scope, v|
      scope.where(production_order_id: Mes::ProductionOrder.joins(:owner)
                                                           .where('users.name ILIKE ?', "%#{v}%").select(:id))
    },
    q: ->(scope, v) { scope.where(SEARCH_SQL, q: "%#{v}%") },
    # 过账时间区间：单边留空＝只卡一头；到日那天整天都算在内，所以补到 23:59:59。
    posted_from: ->(scope, v) { scope.where('mes_stock_entries.posted_at >= ?', v) },
    posted_to: ->(scope, v) { scope.where('mes_stock_entries.posted_at <= ?', "#{v} 23:59:59") }
  }.freeze
  # 工单号对采购入库单要从采购单那边回落取（见 _mes_stock_entry.json.jbuilder），
  # 不预加载就是每行两次查库。
  LIST_EAGER_LOADS = [{ production_order: %i[owner crm_product] }, { purchase_order: { production_order: %i[owner crm_product] } }].freeze

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_stock_entries))
    COLUMN_FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    scope = apply_column_filters(scope)
    @stock_entries_count = scope.count
    @stock_entries = scope.includes(LIST_EAGER_LOADS).order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @stock_entry = Current.account.mes_stock_entries.new(
      stock_entry_params.merge(owner_id: stock_entry_params[:owner_id] || current_user.id)
    )
    # 成品入库(MANUFACTURE)由车间(report)开单；其余库存单仍限仓管(stock)。
    raise Pundit::NotAuthorizedError if @stock_entry.purpose != 'MANUFACTURE' && !Current.account_user.mes_can?(:stock)

    # 收货单据号改到收货明细每项备注上填写，不再强制上传收货单文件。
    @stock_entry.fallback_product_line = current_product_line
    resolve_manufacture_product_ids(@stock_entry)
    @stock_entry.save!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue Pundit::NotAuthorizedError
    raise # 权限不足要回 403，别被下面的 422 吞掉
  rescue StandardError => e
    # 这里抛的多是业务校验（如「订单没关联产品档案」），本该是红字提示；
    # 原先没 rescue，车间开成品入库单时直接弹黑框 Internal Server Error，
    # 写得很清楚的那句话用户一个字也看不到（2026-10-09 生产反馈）。
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 建单前把收货单文件暂存为 blob，拿到 signed_id，建单时通过 receipts 一并挂载。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  def update
    raise Pundit::NotAuthorizedError if @stock_entry.purpose != 'MANUFACTURE' && !Current.account_user.mes_can?(:stock)

    @stock_entry.update!(stock_entry_params)
    render 'api/v1/accounts/mes/stock_entries/show'
  end

  def destroy
    raise StandardError, '已过账单据不能直接删除，请用「作废」冲销库存' if @stock_entry.status == 'POSTED'

    @stock_entry.destroy!
    head :ok
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 作废（冲销）：反向冲回已过账扣的库存、按需回退生产订单阶段，置「已作废」保留可追溯。
  def cancel
    @stock_entry.cancel!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 过账：刷结存 + 记流水 + 阶段推进。
  def post
    @stock_entry.post!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 财务审核：通过。审核人由「入库审核人」配置决定，没配就回落到财务/管理员
  # （见 Mes::StockEntry.approver?）。
  def approve
    ensure_approver!
    @stock_entry.approve!(current_user)
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 财务审核：驳回。必须写原因——仓管要照着原因改单。
  def reject
    ensure_approver!
    @stock_entry.reject!(current_user, params[:reason])
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  # 成品入库：仓管清点数量确认（stock 能力），确认后直接过账入库。
  def confirm_warehouse
    @stock_entry.confirm_warehouse!(current_user)
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: business_error(e) }, status: :unprocessable_entity
  end

  private

  def apply_column_filters(scope)
    COLUMN_LIKE_FILTERS.each do |param, apply|
      value = params[param]
      scope = apply.call(scope, value.to_s.strip) if value.present?
    end
    scope
  end

  # 删草稿不止制单人：成品入库是车间开单、仓管清点，重复单恰恰是仓管在清点时发现的，
  # 只许制单人删就成了死锁——生产上 6 张重复成品入库草稿卡了 34 天没人删得掉。
  # 仓管（stock 能力）可以删；destroy 本身已经把已过账单挡在外面。
  def ensure_can_delete!
    return if Current.account_user.mes_can?(:stock)

    ensure_owner_or_admin!(@stock_entry, '入库单')
  end

  def ensure_approver!
    raise Pundit::NotAuthorizedError unless Mes::StockEntry.approver?(Current.account, Current.account_user)
  end

  def fetch_stock_entry
    @stock_entry = Current.account.mes_stock_entries.find(params[:id])
  end

  # DocumentReturnable 钩子
  def returnable_record = Current.account.mes_stock_entries.find(params[:id])

  def render_returnable(record)
    @stock_entry = record
    render 'api/v1/accounts/mes/stock_entries/show'
  end

  def check_authorization
    authorize(Mes::StockEntry)
  end

  # 完工入库(MANUFACTURE)若成品明细缺商品编码（建单时成品名选填导致），按订单成品名兜底建/关联，
  # 保证成品库存按 SKU 记、不同型号不串到同一个 NULL 桶。
  def resolve_manufacture_product_ids(entry)
    return unless entry.purpose == 'MANUFACTURE'

    order = entry.production_order
    return if order.nil?

    # 完工入库明细均为成品，缺编码的按订单成品名**关联**已有档案——绝不自动建档。
    items = entry.stock_entry_items.select { |i| i.crm_product_id.blank? }
    return if items.empty?

    pid = order.link_crm_product_by_name!
    if pid.blank?
      raise StandardError, "生产订单 #{order.order_no} 没有关联产品档案（成品「#{order.product_name}」在档案里找不到同名项），" \
                           '请先到生产订单上选好成品编码再开成品入库单'
    end

    items.each { |i| i.crm_product_id = pid }
  end

  def stock_entry_params
    params.require(:stock_entry).permit(
      :purpose, :production_order_id, :purchase_order_id, :from_warehouse_id, :to_warehouse_id,
      :is_checked, :checked_by_id, :received_by_id, :owner_id, :remark, :actual_inbound_date, :color,
      # 一张入库单可同时收几张采购单的货（主单之外再挂几张）
      { extra_purchase_order_ids: [] },
      stock_entry_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :qty, :received_qty, :unit, :warehouse_id, :remark, :_destroy,
        # 行内附图：传 signed_id 数组，整组替换（同采购明细）
        { images: [] }
      ]
    )
  end
end
