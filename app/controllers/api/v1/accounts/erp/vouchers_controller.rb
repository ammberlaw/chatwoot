# 记账凭证：手工凭证的增删改 + 过账/红冲/作废。
# 硬规则在 Erp::Voucher / VoucherLine / VoucherPostingService 里，控制器只做取数与状态闸。
class Api::V1::Accounts::Erp::VouchersController < Api::V1::Accounts::Erp::BaseController
  before_action :check_authorization
  before_action :fetch_voucher, only: [:show, :update, :destroy, :post_voucher, :reverse, :void, :attach, :detach]

  def index
    scope = filtered_scope
    @vouchers_count = scope.count
    @vouchers = scope.includes(:prepared_by, :posted_by, :reversal_of, :reversed_by, :documents_attachments)
                     .order(voucher_date: :desc, voucher_no: :desc)
                     .page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @voucher = Current.account.erp_vouchers.new(voucher_params)
    @voucher.prepared_by_id = current_user.id
    @voucher.save!
    @voucher.refresh_totals!
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def update
    return render json: { error: '已记账/已作废的凭证不能修改，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.update!(voucher_params)
    @voucher.refresh_totals!
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def destroy
    return render json: { error: '已记账的凭证不能删除，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.destroy!
    head :ok
  end

  # 过账（记账）：借贷平衡校验通过才置 POSTED。
  def post_voucher
    Erp::VoucherPostingService.new(@voucher, current_user).post!
    render 'api/v1/accounts/erp/vouchers/show'
  rescue Erp::VoucherPostingService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 红冲：生成方向相反的凭证，两张互相引用。
  def reverse
    @voucher = Erp::VoucherPostingService.new(@voucher, current_user).reverse!
    render 'api/v1/accounts/erp/vouchers/show'
  rescue Erp::VoucherPostingService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 作废：只作用于待过账凭证，留痕不删。
  def void
    return render json: { error: '已记账的凭证不能作废，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.update!(status: Erp::Voucher::VOID)
    render 'api/v1/accounts/erp/vouchers/show'
  end

  # 原始单据影像。已过账凭证也放行——补一张扫描件不改账，不该逼人红冲重做。
  def attach
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if params[:files].blank?

    @voucher.documents.attach(params[:files])
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def detach
    @voucher.documents.find(params[:attachment_id]).purge
    @voucher.reload
    render 'api/v1/accounts/erp/vouchers/show'
  end

  # 常用摘要：从已录的分录摘要里按使用频次取，越常用排越前。不另建摘要库表。
  def summaries
    scope = Current.account.erp_voucher_lines.where.not(summary: [nil, ''])
    scope = scope.where('summary ILIKE ?', "%#{params[:q].strip}%") if params[:q].present?
    render json: { payload: scope.group(:summary).order(Arel.sql('COUNT(*) DESC')).limit(20).count.keys }
  end

  # 批量导入：CSV 逐组建待过账凭证，一张凭证有错就整张跳过并报错。
  def import
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if params[:file].blank?

    result = Erp::VoucherImportService.new(Current.account, current_user).import!(params[:file].read.force_encoding('UTF-8'))
    render json: result
  rescue Erp::VoucherImportService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def import_template
    send_data "\xEF\xBB\xBF#{Erp::VoucherImportService.template_csv}",
              filename: '凭证导入模板.csv', type: 'text/csv'
  end

  private

  def filtered_scope
    scope = Current.account.erp_vouchers
    scope = scope.where(period: params[:period]) if params[:period].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    filtered_by_date_and_keyword(scope)
  end

  def filtered_by_date_and_keyword(scope)
    date_range = Range.new(params[:from].presence, params[:to].presence) if params[:from].present? || params[:to].present?
    scope = scope.where(voucher_date: date_range) if date_range
    return scope if params[:q].blank?

    scope.where('voucher_no ILIKE :t OR summary ILIKE :t', t: "%#{params[:q].strip}%")
  end

  # 分录票面要渲染 5 个维度的名字（_erp_voucher_line 局部模板），不预加载就是每行 5 次查询。
  LINE_INCLUDES = [:ledger_account, :crm_customer, :mes_supplier, :crm_sales_order, :department, :member].freeze

  def fetch_voucher
    @voucher = Current.account.erp_vouchers
                      .includes(:documents_attachments, lines: LINE_INCLUDES)
                      .find(params[:id])
  end

  def check_authorization
    authorize(Erp::Voucher)
  end

  def voucher_params
    params.require(:voucher).permit(
      :voucher_date, :summary, :remark, :attachment_count,
      lines_attributes: [
        :id, :ledger_account_id, :direction, :summary, :amount_micros, :currency, :exchange_rate, :position,
        :crm_customer_id, :mes_supplier_id, :crm_sales_order_id, :department_id, :member_id,
        :cash_flow_item, :_destroy
      ]
    )
  end
end
