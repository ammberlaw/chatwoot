class Api::V1::Accounts::Mes::ProductsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_product, only: [:update, :destroy]

  # 产品档案（复用 CRM 产品库 Crm::Product）。MES 侧入口，供 BOM/采购/出库选成品。
  # 读全员可见；增删改仅工程与 PMC（Mes::ProductPolicy → mes_can?(:product)）。
  def index
    scope = scoped_by_product_line(Current.account.crm_products)
    scope = scope.active if params[:filter] == 'active'
    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where(source_category: params[:source_category]) if params[:source_category].present?
    scope = filter_by_group(scope) if params[:group_code].present?
    if params[:q].present?
      scope = scope.where(
        'sku ILIKE :q OR name ILIKE :q OR source_category ILIKE :q OR specification ILIKE :q',
        q: "%#{params[:q].strip}%"
      )
    end
    @products_count = scope.count
    # 按商品编码排，id 兜底。原来按 updated_at 排是错的：4800+ 条产品是一次导入进来的、
    # 共用同一个 updated_at，全序不唯一 → 同一条在每页都冒出来、另一批在任何一页都翻不到
    # （和销售订单那次丢单是同一个毛病）。编码序也和金蝶的档案列表一致，便于对账。
    @products = scope.order(Arel.sql('crm_products.sku ASC NULLS LAST, crm_products.id ASC'))
                     .page(page_param).per(per_page_param)
    # 本页各产品的实时库存（跨仓合计），供 BOM/采购选料即时显示「对应物料实时库存」。
    @onhand_map = Mes::StockBalance.where(account_id: Current.account.id, crm_product_id: @products.map(&:id))
                                   .group(:crm_product_id).sum(:qty)
  end

  # 商品类别树：产品线 → 商品类别（source_category）+ 各自条数。
  # 直接按金蝶那列「商品类别」来，不另起一套要人工维护、最终必然和金蝶对不上的分类字典。
  # 不分页、不带产品明细，只回 (产品线, 类别, 条数)，左侧树一次拉完。
  def categories
    rows = scoped_by_product_line(Current.account.crm_products)
           .group(:product_line, :source_category).count
    ranks = category_ranks
    @category_tree = rows.group_by { |(line, _), _| line.to_s }
                         .transform_values do |entries|
      entries.map { |(line, cat), count| { category: cat.to_s, count: count, line: line.to_s } }
             .sort_by { |c| [ranks[[c[:line], c[:category]]] || Float::INFINITY, c[:category]] }
             .map { |c| c.slice(:category, :count) }
    end.sort.to_h
  end

  # 拖拽排序：按传入顺序把「产品线 + 类别」写成 option_item 的 position。
  # 类别本身不是实体（只是产品上的一个字符串），所以这里的记录纯粹用来记顺序，
  # 类别改名/消失了留着也无害——下次 categories 里查不到它就自然不显示。
  def reorder_categories
    line = current_product_line.to_s
    prefix = line.presence || 'ALL'
    # 一次取回现有记录，避免逐条 SELECT；位置没变的行 update! 不产生 SQL。
    existing = Current.account.crm_option_items.for_category(CATEGORY_SORT_KEY).index_by(&:code)
    Array(params[:categories]).each_with_index do |raw, index|
      name = raw.to_s.presence || BLANK_CATEGORY
      code = "#{prefix}::#{name}"
      item = existing[code] || Current.account.crm_option_items.new(category: CATEGORY_SORT_KEY, code: code)
      item.update!(name: name, product_line: line.presence, position: index)
    end
    head :ok
  end

  def create
    @product = Current.account.crm_products.create!(product_params)
  end

  def update
    @product.update!(product_params)
  end

  def destroy
    @product.destroy!
    head :ok
  end

  private

  # 类别顺序存在 option_item 里（category 固定这个值），code 带产品线前缀，
  # 这样平板的「主板」和商显的「主板」各自记各自的顺序，互不覆盖。
  CATEGORY_SORT_KEY = 'product_source_category'.freeze
  # 「未填类别」也要能拖。option_item 的 name 不允许为空，所以空类别用占位串存，
  # 读回来再映射成空字符串——否则它排不进顺序、永远被挤到列表末尾。
  BLANK_CATEGORY = '__BLANK__'.freeze

  # (产品线, 类别) → 人工顺序。没拖过的类别查不到，排在拖过的后面、按名字兜底。
  def category_ranks
    Current.account.crm_option_items
           .for_category(CATEGORY_SORT_KEY)
           .pluck(:product_line, :name, :position)
           .to_h { |line, name, position| [[line.to_s, name == BLANK_CATEGORY ? '' : name.to_s], position] }
  end

  # 按分组筛选：点某分组连带其整棵子树的产品（收集该节点 + 全部后代的 code）。
  def filter_by_group(scope)
    node = Current.account.crm_option_items.for_category('product_group').find_by(code: params[:group_code])
    return scope.none if node.nil?

    codes = Current.account.crm_option_items.where(id: node.self_and_descendant_ids).pluck(:code)
    scope.where(group_code: codes)
  end

  # 默认 15/页（产品档案列表）；商品编码选择器等可传 per_page 取更多，封顶 100。
  def per_page_param
    n = params[:per_page].to_i
    return RESULTS_PER_PAGE if n <= 0

    [n, 100].min
  end

  def fetch_product
    @product = Current.account.crm_products.find(params[:id])
  end

  def check_authorization
    authorize(Crm::Product, policy_class: Mes::ProductPolicy)
  end

  def product_params
    params.require(:product).permit(
      :name, :sku, :category, :source_category, :specification, :unit, :product_line,
      :cost_price_micros, :sale_price_micros, :pricing_currency, :is_active, :remark, :group_code
    )
  end
end
