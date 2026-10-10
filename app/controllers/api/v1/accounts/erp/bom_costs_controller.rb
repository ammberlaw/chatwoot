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
