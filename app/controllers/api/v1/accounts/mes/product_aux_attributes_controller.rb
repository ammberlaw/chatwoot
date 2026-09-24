# 产品辅助属性维护：同一物料编码下的可选变体（喷码6000 / 喷码3500…）。
#
# 挂在产品下面而不是做成全局字典——同名的「喷码6000」在不同电池上不是一回事，
# 编码也要跟着物料走（P.07.009_001）。
class Api::V1::Accounts::Mes::ProductAuxAttributesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_product
  before_action :fetch_attribute, only: [:update, :destroy]

  def index
    @attributes = @product.aux_attributes.ordered
  end

  def create
    @attribute = @product.aux_attributes.create!(
      account_id: Current.account.id, **attribute_params.to_h.symbolize_keys
    )
    render 'api/v1/accounts/mes/product_aux_attributes/show'
  end

  def update
    @attribute.update!(attribute_params)
    render 'api/v1/accounts/mes/product_aux_attributes/show'
  end

  # 停用而非物理删除：已被历史单据选过的属性删掉会让那些单据失去来历。
  # 从没被选过的才真删，避免属性列表被废弃项越堆越长。
  def destroy
    if Mes::BomItem.exists?(crm_product_aux_attribute_id: @attribute.id)
      @attribute.update!(is_active: false)
      render json: { payload: { deactivated: true } }
    else
      @attribute.destroy!
      render json: { payload: { deactivated: false } }
    end
  end

  private

  def fetch_product
    @product = Current.account.crm_products.find(params[:product_id])
  end

  def fetch_attribute
    @attribute = @product.aux_attributes.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Product, policy_class: Mes::ProductPolicy)
  end

  # code 由模型按 <物料编码>_<序号> 自动生成，不开放给前端传。
  def attribute_params
    params.require(:aux_attribute).permit(:name, :position, :is_active)
  end
end
