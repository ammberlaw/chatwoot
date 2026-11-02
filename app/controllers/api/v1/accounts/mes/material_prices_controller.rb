class Api::V1::Accounts::Mes::MaterialPricesController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_material_price, only: [:update, :destroy]

  # 列表：按物料编码/名称/规格搜。名称与规格从商品档带，不在本表存副本。
  def index
    scope = Current.account.mes_material_prices.includes(:crm_product, :updated_by).joins(:crm_product)
    if params[:q].present?
      scope = scope.where(
        'crm_products.sku ILIKE :t OR crm_products.name ILIKE :t OR crm_products.specification ILIKE :t',
        t: "%#{params[:q].strip}%"
      )
    end
    @material_prices_count = scope.count
    @material_prices = scope.order('crm_products.sku').page(page_param).per(per_page_param)
    @purchase_marks = recent_purchase_marks(@material_prices.map(&:crm_product_id))
  end

  def create
    @material_price = Current.account.mes_material_prices.new(material_price_params.merge(updated_by: current_user))
    @material_price.save!
    render 'api/v1/accounts/mes/material_prices/show'
  end

  def update
    @material_price.update!(material_price_params.except(:crm_product_id).merge(updated_by: current_user))
    render 'api/v1/accounts/mes/material_prices/show'
  end

  def destroy
    @material_price.destroy!
    head :ok
  end

  # Excel 批量导入（物料编码 / 单价）。财务那边的现有单价表贴进来就行，
  # 对不上商品档的行整行退回并列出来，不自动建档。
  def import
    return render json: { error: '请选择要导入的 Excel 文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Mes::MaterialPriceImportService.new(account: Current.account, user: current_user,
                                                 path: params[:file].tempfile.path).import!
    render json: { payload: result }
  rescue Mes::MaterialPriceImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 缺价清单：生产任务单用到、但本表和采购单都没有价的物料。
  # 给采购/财务当补录工作单，比「覆盖率 17%」这种数字有用。
  def missing
    @missing = Mes::MissingPriceFinder.new(account: Current.account).perform
    render 'api/v1/accounts/mes/material_prices/missing'
  end

  # 从历史采购单回填标准价：每颗料取**最近一次**审批通过、未作废的采购单价。
  #
  # 这张表生产上一条都没有（2026-10-29 财务提「采购单价没有数据库」），而 300 多颗料
  # 在采购单里本来就有真实成交价——与其让采购一颗颗敲，直接把采购价搬过来当起点。
  #
  # ⚠️ 只填**空缺**：本表已经有的那颗料一律跳过，不拿采购价盖掉财务手工维护的标准价。
  def backfill_from_purchases
    prices = recent_purchase_prices
    fresh = prices.except(*Current.account.mes_material_prices.pluck(:crm_product_id))
    ActiveRecord::Base.transaction do
      fresh.each do |product_id, rate|
        Current.account.mes_material_prices.create!(
          crm_product_id: product_id, unit_price_micros: rate, updated_by: current_user,
          remark: '从历史采购单回填（最近一次采购价）'
        )
      end
    end
    render json: { payload: { created: fresh.size, skipped: prices.size - fresh.size } }
  end

  private

  # 本页这些料「上次买花了多少、找谁买的、一共买过几次」。
  #
  # 标准价这张表自己只有一个数，光看它判断不了「这价还作不作数」——
  # 得拿真实成交价对一对。口径同 Mes::LastPurchasePrice（审批通过、未作废、有价），
  # 所以这里显示的和采购单上带出来的是同一个数。
  #
  # 一次查完本页 25 行，不逐行往返。
  def recent_purchase_marks(product_ids)
    return {} if product_ids.blank?

    items = Mes::PurchaseItem.joins(:purchase_order).includes(:purchase_order, :mes_supplier)
                             .where(account_id: Current.account.id, crm_product_id: product_ids)
                             .where(mes_purchase_orders: { approval_status: Mes::MaterialPriceResolver::APPROVED_PO })
                             .where.not(mes_purchase_orders: { status: Mes::MaterialPriceResolver::VOID_PO_STATUS })
                             .where('mes_purchase_items.rate_micros > 0')
                             .order('mes_purchase_orders.created_at DESC')
    items.group_by(&:crm_product_id).transform_values { |rows| mark_of(rows) }
  end

  def mark_of(rows)
    latest = rows.first
    { rate_micros: latest.rate_micros, price_tax_included: latest.price_tax_included,
      supplier_name: latest.mes_supplier&.name, po_no: latest.purchase_order&.po_no,
      ordered_at: latest.purchase_order&.created_at, times: rows.size,
      supplier_count: rows.filter_map(&:mes_supplier_id).uniq.size }
  end

  # { crm_product_id => rate_micros }。口径和 Mes::MaterialPriceResolver 的「最近采购价」
  # 一致（审批通过、未作废、有价），所以回填进来的数和任务单上原来兜底显示的是同一个。
  # 按时间升序 pluck 再 to_h：后写覆盖先写，留下的是最近那次。
  def recent_purchase_prices
    Mes::PurchaseItem.joins(:purchase_order)
                     .where(account_id: Current.account.id)
                     .where(mes_purchase_orders: { approval_status: Mes::MaterialPriceResolver::APPROVED_PO })
                     .where.not(mes_purchase_orders: { status: Mes::MaterialPriceResolver::VOID_PO_STATUS })
                     .where('mes_purchase_items.rate_micros > 0')
                     .where.not(crm_product_id: nil)
                     .order('mes_purchase_orders.created_at ASC')
                     .pluck(:crm_product_id, :rate_micros)
                     .to_h
  end

  def fetch_material_price
    @material_price = Current.account.mes_material_prices.find(params[:id])
  end

  def check_authorization
    authorize(Mes::MaterialPrice)
  end

  def per_page_param
    n = params[:per_page].to_i
    n.positive? ? [n, 500].min : 25
  end

  def material_price_params
    params.require(:material_price).permit(:crm_product_id, :unit_price_micros, :remark)
  end
end
