class Api::V1::Accounts::Mes::StockEntriesController < Api::V1::Accounts::Mes::BaseController
  include Api::V1::Accounts::Mes::DocumentReturnable

  before_action :check_authorization
  before_action :fetch_stock_entry, only: [:show, :update, :destroy, :post, :confirm_warehouse, :cancel]

  COLUMN_FILTERS = {
    purpose: :purpose, status: :status,
    production_order_id: :production_order_id, purchase_order_id: :purchase_order_id
  }.freeze

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_stock_entries))
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    @stock_entries_count = scope.count
    @stock_entries = scope.order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
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
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 作废（冲销）：反向冲回已过账扣的库存、按需回退生产订单阶段，置「已作废」保留可追溯。
  def cancel
    @stock_entry.cancel!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 过账：刷结存 + 记流水 + 阶段推进。
  def post
    @stock_entry.post!
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 成品入库：仓管清点数量确认（stock 能力），确认后直接过账入库。
  def confirm_warehouse
    @stock_entry.confirm_warehouse!(current_user)
    render 'api/v1/accounts/mes/stock_entries/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

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

    # 完工入库明细均为成品，缺编码的按订单成品名兜底建/关联。
    items = entry.stock_entry_items.select { |i| i.crm_product_id.blank? }
    return if items.empty?

    pid = order.ensure_crm_product!
    items.each { |i| i.crm_product_id = pid } if pid.present?
  end

  def stock_entry_params
    params.require(:stock_entry).permit(
      :purpose, :production_order_id, :purchase_order_id, :from_warehouse_id, :to_warehouse_id,
      :is_checked, :checked_by_id, :received_by_id, :owner_id, :remark, :actual_inbound_date, :color,
      stock_entry_items_attributes: [
        :id, :item_type, :mes_material_id, :crm_product_id, :qty, :received_qty, :unit, :warehouse_id, :remark, :_destroy
      ]
    )
  end
end
