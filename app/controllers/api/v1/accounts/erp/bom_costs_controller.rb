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
  end

  # 这个成品编码下的物料明细（点开那一行才拉）。
  # 不在列表里一次性带出来：161 个编码、每个几十行物料，一次响应就几兆。
  #
  # 取最新一张 BOM 的明细。同一个成品可能做过多张 BOM（不同订单/改版），
  # 默认 BOM 生产上一张都没维护，所以按 id 倒序取最近那张，并把来源单号摆出来，
  # 让人知道这份用料是哪张单的——不说清楚会被当成"这个产品的标准用料"。
  def materials
    bom_cost = Current.account.erp_bom_costs.find(params[:id])
    bom = Current.account.mes_boms
                 .where(crm_product_id: bom_cost.crm_product_id)
                 .includes(:bom_items).order(is_default: :desc, id: :desc).first
    render json: {
      payload: {
        bom_no: bom&.bom_no, doc_no: bom&.doc_no, base_qty: bom&.base_qty,
        is_default: bom&.is_default,
        items: bom ? bom.bom_items.map { |i| material_json(i) } : []
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

  private

  # 单价取 BOM 行上存的 rate_micros——那是做这张 BOM 时的料价，和 amount 自洽。
  # 不去现查最近采购价：现查会让单价和金额对不上（金额是按当时的价算的）。
  def material_json(item)
    { material_no: item.material_no, material_name: item.material_name,
      specification: item.specification, category: item.category,
      qty: item.qty.to_f, unit: item.unit,
      rate_micros: item.rate_micros, amount_micros: item.amount_micros }
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

  def bom_cost_params
    params.require(:bom_cost).permit(:crm_product_id, :process_fee_micros, :overhead_fee_micros, :remark)
  end
end
