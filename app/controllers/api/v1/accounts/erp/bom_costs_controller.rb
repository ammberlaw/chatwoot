class Api::V1::Accounts::Erp::BomCostsController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_bom_cost, only: [:update, :destroy]

  # 列表：按商品编码/名称/规格搜。产品名称与规格从产品档案带，不在本表存副本。
  def index
    scope = Current.account.erp_bom_costs.includes(:crm_product, :updated_by)
    scope = scope.joins(:crm_product).where(
      'crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t',
      t: "%#{params[:q].strip}%"
    ) if params[:q].present?
    @bom_costs_count = scope.count
    @bom_costs = scope.joins(:crm_product).order('crm_products.sku').page(page_param).per(per_page_param)
    # 按 BOM 现算的单台材料成本，给材料成本栏为 0 的行兜底显示（见 Erp::BomMaterialCostService）。
    # 不落库：材料成本栏手工填的那批是财务认过的数，不该被现查的采购价冲掉。
    @bom_materials = Erp::BomMaterialCostService.new(Current.account,
                                                     @bom_costs.map(&:crm_product_id)).perform
  end

  # 这个成品编码下的物料明细（点开那一行才拉）。
  # 不在列表里一次性带出来：161 个编码、每个几十行物料，一次响应就几兆。
  #
  # 取最新一张 BOM 的明细。同一个成品可能做过多张 BOM（不同订单/改版），
  # 默认 BOM 生产上一张都没维护，所以按 id 倒序取最近那张，并把来源单号摆出来，
  # 让人知道这份用料是哪张单的——不说清楚会被当成"这个产品的标准用料"。
  def materials
    bom_cost = Current.account.erp_bom_costs.find(params[:id])
    service = Erp::BomMaterialCostService.new(Current.account, [bom_cost.crm_product_id])
    result = service.perform[bom_cost.crm_product_id]
    return render json: { payload: { items: [] } } if result.nil?

    bom = result.bom
    render json: {
      payload: {
        bom_no: bom.bom_no, doc_no: bom.doc_no, base_qty: bom.base_qty,
        is_default: bom.is_default,
        # 整单料金额、单台材料成本、几行没查到价——缺价行数必须摆出来，
        # 不标缺口的合计会被当成完整成本用。
        total_micros: result.total_micros, unit_micros: result.unit_micros,
        unpriced_count: result.unpriced_count,
        items: result.items.map { |i| material_json(i, service) }
      }
    }
  end

  def create
    @bom_cost = Current.account.erp_bom_costs.new(bom_cost_params.merge(updated_by: current_user))
    @bom_cost.save!
    render 'api/v1/accounts/erp/bom_costs/show'
  end

  def update
    @bom_cost.update!(bom_cost_params.except(:crm_product_id).merge(updated_by: current_user))
    render 'api/v1/accounts/erp/bom_costs/show'
  end

  def destroy
    @bom_cost.destroy!
    head :ok
  end

  # Excel 批量导入（商品编码 / 产品名称 / 规格型号 / 加工费 / 制造费用）。
  # 产品名称与规格只用来给人对照，落库只认**商品编码**；对不上产品档案的整行退回，
  # 不自动建档——编码写错了自动建档只会在产品档案里堆垃圾。
  def import
    return render json: { error: '请选择要导入的 Excel 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Erp::BomCostImportService.new(account: Current.account, user: current_user,
                                           path: params[:file].tempfile.path).import!
    render json: { payload: result }
  rescue Erp::BomCostImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ── 制造费用按月分摊 ───────────────────────────────────────────
  # 上面那两栏（人工费 / 制造费用）是**标准单价**，每台永远一样。
  # 这里是财务要的另一种口径：当月 5101 实际发生额 ÷ 当月完工入库总量，按各单入库量摊回去。
  # preview 只算不写——财务要先看分子分母对不对才敢落账；allocate 才写 erp_order_costs。
  def overhead_preview
    render json: { payload: with_order_no(overhead_service.preview(params[:period])) }
  rescue Erp::OverheadAllocationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def overhead_allocate
    render json: { payload: with_order_no(overhead_service.allocate!(params[:period])) }
  rescue Erp::OverheadAllocationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # 单价现查（标准价 → 最近采购价），不取 BOM 行上存的 rate_micros：
  # 生产任务单的物料清单没有录价的入口，那两列落库 1223 行全是 0，摆出来就是一片 0.00。
  # 金额按现查的价重算，和单价自洽；价源标出来，让人知道这个数是哪来的。
  def material_json(item, service)
    price = service.price_for(item)
    { material_no: item.material_no, material_name: item.material_name,
      specification: item.specification, category: item.category,
      qty: item.qty.to_f, unit: item.unit,
      rate_micros: price&.dig(:price_micros), amount_micros: service.priced_amount(item),
      price_source: price&.dig(:source), price_source_label: price&.dig(:source_label) }
  end

  def fetch_bom_cost
    @bom_cost = Current.account.erp_bom_costs.find(params[:id])
  end

  def check_authorization
    authorize(Erp::BomCost)
  end

  def per_page_param
    n = params[:per_page].to_i
    n.positive? ? [n, 500].min : 25
  end

  def overhead_service
    Erp::OverheadAllocationService.new(Current.account)
  end

  # 服务只给 production_order_id，界面上要看得出是哪张单、什么产品。
  def with_order_no(result)
    orders = Current.account.mes_production_orders
                    .where(id: result[:rows].map { |r| r[:production_order_id] })
                    .pluck(:id, :order_no, :product_name).to_h { |id, no, name| [id, [no, name]] }
    rows = result[:rows].map do |row|
      no, name = orders[row[:production_order_id]]
      row.merge(order_no: no, product_name: name)
    end
    result.merge(rows: rows)
  end

  def bom_cost_params
    params.require(:bom_cost).permit(:crm_product_id, :material_cost_micros, :process_fee_micros,
                                    :overhead_fee_micros, :packaging_cost_micros,
                                    :cost_source, :cost_as_of, :remark)
  end
end
