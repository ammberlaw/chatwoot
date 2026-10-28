class Api::V1::Accounts::Mes::ProductionRecordsController < Api::V1::Accounts::Mes::BaseController
  include Api::V1::Accounts::Mes::DocumentReturnable

  before_action :check_authorization

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_production_records))
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    scope = apply_search(scope, params[:q])
    @production_records_count = scope.count
    @production_records = scope.order(recorded_at: :desc, id: :desc).page(page_param).per(per_page_param)
  end

  def create
    @production_record = Current.account.mes_production_records.create!(
      production_record_params.merge(operator_id: production_record_params[:operator_id] || current_user.id)
    )
    render 'api/v1/accounts/mes/production_records/show'
  end

  def destroy
    record = Current.account.mes_production_records.find(params[:id])
    ensure_owner_or_admin!(record, '报工记录', :operator_id)
    return if performed?

    po = record.production_order
    # 删报工会回退已产量；若已产量会因此低于「已成品入库量」，先拒绝，须先冲销成品入库单，
    # 否则会出现「入库量 > 产量」的负差错账。
    if po && po.fg_inbound_qty.to_d.positive? &&
       (po.produced_qty.to_d - record.qty_completed.to_d) < po.fg_inbound_qty.to_d
      return render json: { error: "该订单已有成品入库 #{po.fg_inbound_qty.to_i} 件，删除本报工会使已产量低于已入库量，请先冲销对应成品入库单" },
                    status: :unprocessable_entity
    end
    record.destroy!
    head :ok
  end

  private

  # 车间翻记录靠的是工单号和产品名（「K717 那批报了多少」），工序和备注也常用来找返工那几条。
  def apply_search(scope, raw)
    q = raw.to_s.strip
    return scope if q.blank?

    like = "%#{q}%"
    scope.where(production_order_id: searchable_order_ids(like))
         .or(scope.where('mes_production_records.operation_name ILIKE :q OR mes_production_records.remark ILIKE :q', q: like))
  end

  # 工单号/产品名在生产订单上，先查出订单 id 再按 id 过滤（跨表 OR 没法走索引）。
  def searchable_order_ids(like)
    Current.account.mes_production_orders
           .where('order_no ILIKE :q OR product_name ILIKE :q', q: like).select(:id)
  end

  # DocumentReturnable 钩子
  def returnable_record = Current.account.mes_production_records.find(params[:id])

  def render_returnable(record)
    @production_record = record
    render 'api/v1/accounts/mes/production_records/show'
  end

  def check_authorization
    authorize(Mes::ProductionRecord)
  end

  def production_record_params
    params.require(:production_record).permit(
      :production_order_id, :operation_name, :qty_completed, :qty_returned, :qty_scrap, :operator_id, :recorded_at, :remark
    )
  end
end
