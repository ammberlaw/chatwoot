class Api::V1::Accounts::Crm::QuotesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_quote, only: [:show, :update, :destroy, :xlsx, :preview, :convert_to_sales_order, :health_check]

  RESULTS_PER_PAGE = 15
  SUMMARY_STATUSES = Crm::Quote::STATUSES
  XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

  def index
    @quotes_scope = filtered_quotes
    @quotes_count = @quotes_scope.count
    @quotes = @quotes_scope
              .order(quotes_order_clause)
              .page(permitted_params[:page] || 1)
              .per(RESULTS_PER_PAGE)
  end

  # 默认按更新时间倒序；用户点「报价日期」表头排序时改按 quote_date（空值垫底）。
  def quotes_order_clause
    return { updated_at: :desc } if params[:date_dir].blank?

    dir = params[:date_dir] == 'asc' ? 'ASC' : 'DESC'
    Arel.sql("quote_date #{dir} NULLS LAST, id DESC")
  end

  # 页顶汇总：各状态张数 + 按币种金额 + 可见范围内创建人（供筛选）。
  def summary
    scope = scope_docs_visible(Current.account.crm_quotes)
    scope = scope_docs_mine(scope) if params[:filter] == 'mine'

    counts = scope.group(:status).count
    amounts = scope.where.not(total_amount_micros: nil)
                   .group(:status, :quote_currency)
                   .sum(:total_amount_micros)
    render json: build_summary(counts, amounts).merge(creators: creators_for(scope))
  end

  def show; end

  # 在线预览：单据本体 + 模板里固定的那部分（抬头 / 右栏默认条款 / 条款正文 / 页脚），
  # 都从 Crm::QuoteTemplateFiller 取，预览与导出的 Excel 不会各说各话。
    # 发出前体检：算术对不对、条款缺不缺、币种和这家客户以往一不一致、
  # 单价和历史价差多少。纯计算不调模型（见 Crm::DocHealthCheck）。
  def health_check
    findings = Crm::DocHealthCheck.for_quote(@quote)
    render json: { payload: findings.map { |f| { level: f.level, title: f.title, detail: f.detail } } }
  end

def preview
    @static = Crm::QuoteTemplateFiller.static_text
    @seller_lines = Crm::QuoteTemplateFiller.seller_lines_for(@quote)
    @issuer_name = Crm::QuoteTemplateFiller.issuer_name_for(@quote)
    @buyer_contact = Crm::QuoteTemplateFiller.contact_name_for(@quote)
  end

  def create
    @quote = Current.account.crm_quotes.new(quote_params)
    # 业绩归属人 = 客户归属人（共享客户助理建报价，业绩归老板）；handled_by = 实际建单人（留痕）。
    @quote.owner_id ||= performance_owner_id(@quote.crm_customer_id)
    @quote.handled_by_id ||= current_user.id
    @quote.save!
    recompute_totals!
    Crm::OpportunityStageSync.from_quote(@quote.reload)
    render :show
  end

  def update
    @quote.update!(quote_params)
    recompute_totals!
    Crm::OpportunityStageSync.from_quote(@quote.reload)
    render :show
  end

  def destroy
    @quote.destroy!
    head :ok
  end

  # 导出 xlsx：填公司报价单模板 1:1。模板未配置时明确提示（模板由公司提供后接入）。
  def xlsx
    unless quote_template_ready?
      render json: { error: '报价单模板未配置，等公司模板上传后即可导出' }, status: :unprocessable_entity
      return
    end

    stream = Crm::QuoteTemplateFiller.new(@quote).to_stream
    send_data stream.read, filename: "Quote-#{@quote.quote_no}.xlsx", type: XLSX_MIME
  end

  # 报价确认后一键转销售订单（幂等：同一 quote_no 只转一次）。
  def convert_to_sales_order
    order = Crm::QuoteToSalesOrder.new(@quote).call
    return render json: { error: '转单失败，请检查报价明细与客户' }, status: :unprocessable_entity if order.nil?

    render json: { id: order.id, name: order.name }
  rescue StandardError => e
    Rails.logger.error("[Quote->SO] quote=#{@quote.id}: #{e.class} #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 选客户后带出买方信息（业务仍可改）。国家/网址是预览抬头里的两格，顺带给上。
  def prefill
    customer = Current.account.crm_customers.find(params[:customer_id])
    render json: {
      customer_name: customer.name,
      contact_name: customer.primary_contact_name,
      contact_email: customer.contact_email,
      contact_phone: customer.contact_phone,
      trade_country: customer.trade_country,
      website: customer.website,
      quote_currency: customer.currency_preference.presence || 'USD'
    }
  end

  # 新建/编辑时右侧实时预览要的「单据之外」那部分：模板固定文案 + 卖方两行 + 落款。
  # 单据还没落库拿不到 id，所以走 collection；取数与 preview 走同一处，
  # 在线预览、实时预览、导出的 Excel 三者不会各说各话。
  def preview_meta
    owner_id = params[:owner_id].presence || current_user.id
    contact_line, email_line = Crm::QuoteTemplateFiller.seller_lines_for_owner(Current.account.id, owner_id)
    render json: {
      template: Crm::QuoteTemplateFiller.static_text,
      seller: { contact_line: contact_line, email_line: email_line },
      issued_by: Crm::QuoteTemplateFiller.issuer_name_for_owner(Current.account.id, owner_id)
    }
  end

  private

  # 按 id 直取也必须走可见范围收口（与 index 一致），否则任意成员可越权读改他人报价单。
  def fetch_quote
    @quote = scope_docs_visible(Current.account.crm_quotes).find(params[:id])
  end

  def check_authorization
    authorize(Crm::Quote)
  end

  # 小计=明细金额合计；总额=小计−折扣+运费+税（各项前端传，缺省 0）。明细金额已在行模型算好。
  def recompute_totals!
    subtotal = @quote.line_items.sum(:amount_micros)
    total = subtotal - @quote.discount_amount_micros.to_i + @quote.shipping_fee_micros.to_i + @quote.tax_amount_micros.to_i
    # 缓存统计写回，不触发校验/审计。
    @quote.update_columns(subtotal_micros: subtotal, total_amount_micros: total) # rubocop:disable Rails/SkipsModelValidations
  end

  def build_summary(counts, amounts)
    buckets = (['all'] + SUMMARY_STATUSES).index_with { { count: 0, amounts: Hash.new(0) } }

    counts.each do |status, n|
      buckets[status][:count] = n if buckets.key?(status)
      buckets['all'][:count] += n
    end
    amounts.each do |(status, currency), micros|
      cur = currency.presence || 'USD'
      buckets[status][:amounts][cur] += micros if buckets.key?(status)
      buckets['all'][:amounts][cur] += micros
    end
    buckets
  end

  def creators_for(scope)
    User.where(id: scope.where.not(owner_id: nil).select(:owner_id))
        .order(:name)
        .map { |u| { id: u.id, name: u.crm_display_name } }
  end

  def filtered_quotes
    scope = apply_view_filter(scope_docs_visible(Current.account.crm_quotes))
    scope = scope.owned_by(params[:owner_id]) if params[:owner_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope = filter_by_month(scope, params[:month]) if params[:month].present?
    scope = search(scope, params[:q]) if params[:q].present?
    scope
  end

  # 按月份（YYYY-MM）筛选 quote_date 落在该自然月内的报价单。非法值不筛。
  def filter_by_month(scope, month)
    start_date = Date.strptime(month, '%Y-%m')
    scope.where(quote_date: start_date..start_date.end_of_month)
  rescue ArgumentError
    scope
  end

  # 视图档：pending=待处理(DRAFT/SENT)、mine=我的。
  def apply_view_filter(scope)
    return scope.pending if params[:filter] == 'pending'
    return scope_docs_mine(scope) if params[:filter] == 'mine'

    scope
  end

  # 搜索：报价单号 / 名称 / 关联客户名。
  def search(scope, query)
    term = "%#{query.strip}%"
    scope.left_joins(:crm_customer)
         .where('crm_quotes.quote_no ILIKE :t OR crm_quotes.name ILIKE :t OR crm_customers.name ILIKE :t', t: term)
  end

  def quote_params
    params.require(:quote).permit(
      :name, :quote_no, :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id,
      :quote_date, :valid_until, :status, :quote_currency, :exchange_rate,
      :discount_amount_micros, :shipping_fee_micros, :tax_amount_micros, :remark,
      line_items_attributes: [
        :id, :name, :quantity, :unit_price_micros, :spec_snapshot, :remark, :crm_product_id, :picture, :_destroy
      ]
    )
  end

  def quote_template_ready?
    File.exist?(Crm::QuoteTemplateFiller::TEMPLATE)
  end

  def permitted_params
    params.permit(:page, :filter, :status, :owner_id, :q, :customer_id, :month, :date_dir)
  end
end
