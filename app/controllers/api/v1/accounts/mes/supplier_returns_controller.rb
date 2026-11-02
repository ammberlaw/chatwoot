# 采购退料单：把料退回给供应商（换新的 / 不要了），换回来的登记返回。
#
# 2026-10-29 起**真的动库存**：退出去从不良品仓扣，换回来的入回原料仓
# （各自生成一张库存单，见 Mes::SupplierReturn#send_out! / #receive_back!）。
class Api::V1::Accounts::Mes::SupplierReturnsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_return, only: [:show, :update, :destroy, :send_out, :receive_back]

  RESULTS_PER_PAGE = 20

  # 按来源单据筛是新建退料单时用的：要算「这张入库单的货还剩多少能退」＝ 收了多少 − 已退多少。
  FILTERS = { status: :status, production_order_id: :production_order_id,
              source_stock_entry_id: :source_stock_entry_id, return_kind: :return_kind }.freeze

  # 表头上每列各自的筛选（对标金蝶的漏斗）。放后端是因为列表分页：
  # 前端只过滤本页，第 2 页往后的命中就全看不见了。
  COLUMN_LIKE_FILTERS = {
    col_no: ->(scope, v) { scope.where('mes_supplier_returns.return_no ILIKE ?', "%#{v}%") },
    col_supplier: lambda { |scope, v|
      scope.where(mes_supplier_id: Mes::Supplier.where('name ILIKE ?', "%#{v}%").select(:id))
    },
    col_reason: ->(scope, v) { scope.where('mes_supplier_returns.reason ILIKE ?', "%#{v}%") },
    # 「关联单号」那一列显示的是来源采购单号或来源入库单号，两个都得认。
    col_ref: lambda { |scope, v|
      scope.where(
        'mes_supplier_returns.mes_purchase_order_id IN (SELECT id FROM mes_purchase_orders WHERE po_no ILIKE :t) ' \
        'OR mes_supplier_returns.source_stock_entry_id IN (SELECT id FROM mes_stock_entries WHERE entry_no ILIKE :t)',
        t: "%#{v}%"
      )
    },
    # 退出 / 返回是 date 列，到日那天本身算在内，直接按日期比即可（不必补 23:59:59）。
    sent_from: ->(scope, v) { scope.where('mes_supplier_returns.sent_on >= ?', v) },
    sent_to: ->(scope, v) { scope.where('mes_supplier_returns.sent_on <= ?', v) },
    returned_from: ->(scope, v) { scope.where('mes_supplier_returns.returned_on >= ?', v) },
    returned_to: ->(scope, v) { scope.where('mes_supplier_returns.returned_on <= ?', v) }
  }.freeze

  def index
    scope = scoped_by_product_line(Current.account.mes_supplier_returns)
    FILTERS.each { |param, column| scope = scope.where(column => params[param]) if params[param].present? }
    # 建单日期区间（from / to，与采购申请单、采购单同一套参数名）。
    scope = scoped_by_created_range(scope)
    scope = apply_column_filters(scope)
    scope = apply_search(scope, params[:q])
    @returns_count = scope.count
    @returns = scope.includes(:mes_supplier, :production_order, :owner, :warehouse,
                              :mes_purchase_order, :source_stock_entry, :out_stock_entry,
                              items: :crm_product)
                    .order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @supplier_return = Current.account.mes_supplier_returns.new(
      supplier_return_params.merge(owner_id: current_user.id)
    )
    @supplier_return.fallback_product_line = current_product_line
    @supplier_return.save!
    render 'api/v1/accounts/mes/supplier_returns/show'
  end

  def update
    @supplier_return.update!(supplier_return_params)
    render 'api/v1/accounts/mes/supplier_returns/show'
  end

  def destroy
    return render json: { error: '已经退出去的单不能删，请走关闭' }, status: :unprocessable_entity if @supplier_return.sent_on

    @supplier_return.destroy!
    head :ok
  end

  # 退出去：从仓库扣货（生成 PURCHASE_RETURN 出库单）、记日期，进「已退出」。
  def send_out
    render_after { @supplier_return.send_out!(on: params[:sent_on], actor: current_user) }
  end

  # 登记返回：rows = [{ id:, returned_qty: }]，累加到各行的已返回数并入回库存。
  # warehouse_id 不传就回原仓——换回来的是好货，界面上默认给原料仓。
  def receive_back
    render_after do
      @supplier_return.receive_back!(
        params[:rows],
        on: params[:returned_on], warehouse_id: params[:warehouse_id], actor: current_user
      )
    end
  end

  private

  def render_after
    yield
    render 'api/v1/accounts/mes/supplier_returns/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def apply_column_filters(scope)
    COLUMN_LIKE_FILTERS.each do |param, apply|
      scope = apply.call(scope, params[param].to_s.strip) if params[param].present?
    end
    scope
  end

  def apply_search(scope, raw)
    q = raw.to_s.strip
    return scope if q.blank?

    like = "%#{q}%"
    scope.where('mes_supplier_returns.return_no ILIKE :q OR mes_supplier_returns.reason ILIKE :q', q: like)
  end

  def fetch_return
    @supplier_return = Current.account.mes_supplier_returns.find(params[:id])
  end

  def check_authorization
    authorize(Mes::SupplierReturn)
  end

  def supplier_return_params
    params.require(:supplier_return).permit(
      :return_no, :mes_supplier_id, :production_order_id, :product_line, :reason, :remark, :sent_on,
      # 退法（换新的/不要了）、从哪个仓退、关联的采购单与入库单——用户 2026-10-29 点名要的几项。
      :return_kind, :warehouse_id, :mes_purchase_order_id, :source_stock_entry_id,
      items_attributes: [:id, :crm_product_id, :qty, :unit, :unit_price_micros, :remark, :_destroy]
    )
  end
end
