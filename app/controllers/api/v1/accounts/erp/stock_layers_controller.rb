# 成品存货批次层（FIFO）：查看当前批次与结存成本 + 期初导入。
# 成本数据，只对能进 ERP 的人开放（基类门禁），写操作限 close 能力（与期初建账同级）。
class Api::V1::Accounts::Erp::StockLayersController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization

  def index
    scope = filtered_scope
    @layers_count = scope.count
    @layers = scope.order(received_at: :desc, id: :desc).page(page_param).per(per_page_param)
    @summary = summarize(scope)
  end

  def import
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Erp::StockOpeningImportService.new(Current.account, current_user)
                                           .import!(params[:file].read.force_encoding('UTF-8'))
    render json: { payload: result }
  rescue Erp::StockOpeningImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def import_template
    send_data "\xEF\xBB\xBF#{Erp::StockOpeningImportService.template_csv}",
              filename: '成品期初存货模板.csv', type: 'text/csv'
  end

  private

  def filtered_scope
    scope = Current.account.erp_stock_layers.includes(:crm_product, :warehouse)
    scope = scope.where(crm_product_id: params[:crm_product_id]) if params[:crm_product_id].present?
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    # 默认只看还有余量的层；勾「含已耗尽」才把历史批次也列出来（追溯用）。
    params[:include_empty] == 'true' ? scope : scope.where('qty_remaining > 0')
  end

  # 结存合计：数量与金额（金额＝各层剩余×该层单价，这正是存货的账面价值）。
  # 另带 MES 实物结存做对比——批次层是 ERP 的成本账、实物结存是仓库的账，两者本是两本账：
  # 期初漏导、或上核算之前就有的存货，都会让「有货没成本」。差额摆出来，别让它静默。
  def summarize(scope)
    rows = scope.pluck(:qty_remaining, :unit_cost_micros)
    layer_qty = rows.sum(&:first).to_f
    physical = physical_qty
    {
      qty: layer_qty,
      amount_micros: rows.sum { |qty, unit| (qty * unit).round },
      physical_qty: physical,
      diff_qty: (physical - layer_qty).round(3)
    }
  end

  # MES 成品实物结存（同口径过滤：指定了产品/仓库就只比那一格）。
  def physical_qty
    scope = Current.account.mes_stock_balances.where(item_type: 'PRODUCT')
    scope = scope.where(crm_product_id: params[:crm_product_id]) if params[:crm_product_id].present?
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    scope.sum(:qty).to_f
  end

  def check_authorization
    authorize(Erp::StockLayer)
  end
end
