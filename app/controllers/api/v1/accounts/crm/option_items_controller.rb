# CRM 客户设置：客户分组 / 客户来源的自定义项（二级层级 + 显隐 + 排序）。仅管理员/副管理员。
class Api::V1::Accounts::Crm::OptionItemsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_item, only: %i[update destroy]

  # 按类别返回全部项（一级 + 二级，按 position 排）；首次访问按现有枚举播种一级项。
  def index
    category = params[:category].to_s
    Crm::OptionItem.ensure_defaults!(Current.account, category)
    @items = Current.account.crm_option_items.for_category(category).ordered
  end

  def create
    @item = Current.account.crm_option_items.create!(create_params.merge(position: next_position))
    render :show
  end

  def update
    @item.update!(update_params)
    render :show
  end

  def destroy
    @item.destroy!
    head :ok
  end

  # 拖拽排序：按传入 id 顺序写回 position（同一父级/类别内一次提交）。
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    items = Current.account.crm_option_items.where(id: ids).index_by(&:id)
    ids.each_with_index do |id, index|
      items[id]&.update_column(:position, index) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  private

  def fetch_item
    @item = Current.account.crm_option_items.find(params[:id])
  end

  def check_authorization
    authorize(Crm::OptionItem)
  end

  # 新项排到同父级/类别末尾。
  def next_position
    scope = Current.account.crm_option_items
                   .where(category: create_params[:category], parent_id: create_params[:parent_id])
    (scope.maximum(:position) || -1) + 1
  end

  def create_params
    params.require(:option_item).permit(:category, :name, :parent_id)
  end

  def update_params
    params.require(:option_item).permit(:name, :active)
  end
end
