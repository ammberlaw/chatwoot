class Api::V1::Accounts::Mes::ProductGroupsController < Api::V1::Accounts::Mes::BaseController
  # 产品分组树（复用 Crm::OptionItem，category=product_group，不限层级）。
  # 读全员可见（侧栏筛选 + 产品表单选分组）；维护限工程/PMC（Mes::ProductGroupPolicy）。
  CATEGORY = 'product_group'.freeze

  before_action :check_authorization
  before_action :fetch_item, only: %i[update destroy]

  def index
    @items = line_scoped(Current.account.crm_option_items.for_category(CATEGORY)).ordered
  end

  def create
    @item = Current.account.crm_option_items.create!(
      create_params.merge(category: CATEGORY, position: next_position, product_line: current_product_line)
    )
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

  # 拖拽排序：按传入 id 顺序写回 position（同一父级内一次提交）。
  def reorder
    ids = Array(params[:ids]).map(&:to_i)
    items = Current.account.crm_option_items.for_category(CATEGORY).where(id: ids).index_by(&:id)
    ids.each_with_index do |id, index|
      items[id]&.update_column(:position, index) # rubocop:disable Rails/SkipsModelValidations
    end
    head :ok
  end

  private

  # 产品分组按产线分流：切到某条产线时只看该产线的树 + 公共分组（product_line 为空，
  # 即在「全部」下建的）。不这么收口的话，平板产线会看到商显那棵树。
  def line_scoped(scope)
    return scope if current_product_line.blank?

    scope.where(product_line: [current_product_line, nil])
  end

  def fetch_item
    @item = Current.account.crm_option_items.for_category(CATEGORY).find(params[:id])
  end

  def check_authorization
    authorize(Crm::OptionItem, policy_class: Mes::ProductGroupPolicy)
  end

  # 新项排到同父级末尾。
  def next_position
    scope = Current.account.crm_option_items.for_category(CATEGORY).where(parent_id: create_params[:parent_id])
    (scope.maximum(:position) || -1) + 1
  end

  def create_params
    params.require(:product_group).permit(:name, :parent_id)
  end

  def update_params
    params.require(:product_group).permit(:name, :active, :parent_id)
  end
end
