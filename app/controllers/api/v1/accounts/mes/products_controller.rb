class Api::V1::Accounts::Mes::ProductsController < Api::V1::Accounts::Mes::BaseController
  # 成品/裸机（跟着金蝶那列「商品类别」走，不另起一套分类字典）。
  # 选料场景要把它们排除：领料领的是物料，不是整机。
  FINISHED_CATEGORIES = %w[成品 裸机].freeze

  before_action :check_authorization
  before_action :fetch_product, only: [:show, :update, :destroy]

  # 产品档案（复用 CRM 产品库 Crm::Product）。MES 侧入口，供 BOM/采购/出库选成品。
  # 读全员可见；增删改仅工程与 PMC（Mes::ProductPolicy → mes_can?(:product)）。
  def index
    scope = apply_product_filters(scoped_by_product_line(Current.account.crm_products))
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

  # 单条档案：生产任务单里的「页内查改产品档案」抽屉按 id 读这颗料
  # （用料明细带着 product_id，不必再按编码去查一次）。
  def show; end

  # 批量按编码查档案：电子投单单上的整列编码复制过来，一次全查出来，不用一个个手搜。
  # 前缀可有可无（贴 01.033 也认 P.01.033），大小写不敏感；返回按送进来的顺序对齐。
  def lookup
    codes = Array(params[:codes]).map { |c| c.to_s.strip }.reject(&:blank?).first(300)
    return render json: { payload: [] } if codes.empty?

    scope = Current.account.crm_products.includes(:aux_attributes)
    exact = scope.where('UPPER(sku) IN (?)', codes.map(&:upcase)).index_by { |p| p.sku.to_s.upcase }
    # 没精确命中的再按「后缀」找一次：业务贴的往往是去掉 P. 前缀的短码。
    missing = codes.reject { |c| exact.key?(c.upcase) }
    suffix = missing.any? ? scope.where(missing.map { 'UPPER(sku) LIKE ?' }.join(' OR '), *missing.map { |c| "%#{c.upcase}" }) : []
    @lookup_rows = codes.map do |code|
      hit = exact[code.upcase] || suffix.find { |p| p.sku.to_s.upcase.end_with?(code.upcase) }
      { code: code, product: hit }
    end
    render 'api/v1/accounts/mes/products/lookup'
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

  # 列表筛选：启用态 → 搜索/分类（二选一） → 只看物料。
  def apply_product_filters(scope)
    scope = scope.active if params[:filter] == 'active'
    scope = search_or_category(scope)
    # materials_only=1：领料/BOM/采购这些「选料」场景只认物料。
    # 产品档案按编码排序，成品是 P.01 段、裸机是 P.02 段，永远排在最前面——
    # 领料单一点开下拉，第一屏全是成品型号，物料要翻好几页（用户原话：
    # 「这个领料明细模块显示成品状态，看不到物料具体明细」）。
    return scope if params[:materials_only].blank?

    # 这里不能写 where.not：SQL 的 NOT IN 碰上 NULL 返回 NULL 而不是 true，
    # 没填商品类别的料会被一并过滤掉（dev 库整库 source_category 为空，一搜就「无匹配物料」）。
    scope.where('crm_products.source_category IS NULL OR crm_products.source_category NOT IN (?)',
                FINISHED_CATEGORIES)
  end

  # 🔴 搜索时**忽略左侧分类/分组筛选**：用户要找一个编码时，并不知道（也不该关心）
  # 它挂在哪个类别下。原来两者是「与」的关系——选中「触摸屏」再搜 20.002 永远搜不到，
  # 必须先点回「全部」，等于每次搜索前都要先想一下这颗料属于哪类。
  def search_or_category(scope)
    if params[:q].present?
      return scope.where(
        'sku ILIKE :q OR name ILIKE :q OR source_category ILIKE :q OR specification ILIKE :q',
        q: "%#{params[:q].strip}%"
      )
    end

    scope = scope.where(category: params[:category]) if params[:category].present?
    scope = scope.where(source_category: params[:source_category]) if params[:source_category].present?
    params[:group_code].present? ? filter_by_group(scope) : scope
  end

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

  # 默认 15/页；商品编码选择器等可传 per_page 取更多。
  # 封顶放到 1000：产品档案生产上近 5000 条，15 条一页要翻 333 页，
  # 采购编新料号时得翻到同字母的流水号末尾才知道编到几号（用户原话「金蝶是 1000 条/页」）。
  def per_page_param
    n = params[:per_page].to_i
    return RESULTS_PER_PAGE if n <= 0

    [n, 1000].min
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
