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
                     .page(page_param).per(per_page_param)
  end

  def show; end

  def create
    @voucher = Current.account.erp_vouchers.new(voucher_params)
    @voucher.prepared_by_id = current_user.id
    @voucher.save!
    @voucher.refresh_totals!
    attach_staged_documents
    render 'api/v1/accounts/erp/vouchers/show'
  end

  # 建单前先把发票/水单传上来换 signed_id，保存时一并挂到凭证上。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  def update
    return render json: { error: '已记账/已作废的凭证不能修改，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    @voucher.update!(voucher_params)
    @voucher.refresh_totals!
    attach_staged_documents
    render 'api/v1/accounts/erp/vouchers/show'
  end

  def destroy
    return render json: { error: '已记账的凭证不能删除，错账请用红冲' }, status: :unprocessable_entity unless @voucher.editable?

    ActiveRecord::Base.transaction do
      rollback_depreciation_side_effects
      @voucher.destroy!
    end
    head :ok
  end

  # 过账（记账）：借贷平衡校验通过才置 POSTED。
  def post_voucher
    Erp::VoucherPostingService.new(@voucher, current_user).post!
    render 'api/v1/accounts/erp/vouchers/show'
  rescue Erp::VoucherPostingService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 批量过账：把选中的待过账凭证逐张过账。
  #
  # 自动凭证天天在产（出库出收入+成本两张、收付款各一张…），一张一张点三十几张还行，
  # 几百张就没人干了——这正是「凭证天天生成、报表永远是空的」最后那道人力卡口。
  # 逐张 rescue：一张不平不该拖垮整批，失败原因原样带回去，财务照着清单改。
  # 单次封顶 100 张（= 列表每页上限，够「全选本页一键过」），不会撞 15 秒请求时限。
  BULK_POST_LIMIT = 100

  def bulk_post
    # 空数组经表单编码会变成 ['']（to_i 后是 0），不滤掉就会被当成「选了一张」。
    ids = Array(params[:voucher_ids]).map(&:to_i).select(&:positive?).uniq
    return render json: { error: '请先选择要过账的凭证' }, status: :unprocessable_entity if ids.empty?
    return render json: { error: "一次最多过账 #{BULK_POST_LIMIT} 张，请分批操作" }, status: :unprocessable_entity if ids.size > BULK_POST_LIMIT

    render json: { payload: post_each(ids) }
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

    ActiveRecord::Base.transaction do
      rollback_depreciation_side_effects
      @voucher.update!(status: Erp::Voucher::VOID)
    end
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

  # 折旧/处置凭证是草稿时被删/作废，资产侧的计提记录与累计折旧（或处置状态）要一起退回，
  # 否则「资产提了折旧、总账没入账」，而且该期间重新计提会返回 0 张——这个月折旧就丢了。
  # 选中的里面可能混着已过账/已作废的（列表停留在旧数据时很常见），
  # 这些既不算成功也不算失败，单独报个 skipped，免得「选了 30 张、过了 25 张」没人知道另外 5 张去哪了。
  def post_each(ids)
    posted = 0
    failed = []
    Current.account.erp_vouchers.where(id: ids, status: Erp::Voucher::DRAFT).order(:voucher_no).each do |voucher|
      Erp::VoucherPostingService.new(voucher, current_user).post!
      posted += 1
    rescue Erp::VoucherPostingService::Error, ActiveRecord::RecordInvalid => e
      failed << { voucher_no: voucher.voucher_no, error: posting_error(e) }
    end
    { posted: posted, failed: failed, skipped: ids.size - posted - failed.size }
  end

  # RecordInvalid 在中文环境下 message 是「Translation missing: …record_invalid」，
  # 原样返回等于没提示——取逐字段的校验信息（期间已结账就是从这儿冒出来的）。
  def posting_error(error)
    return error.record.errors.full_messages.join('；') if error.is_a?(ActiveRecord::RecordInvalid) && error.record.present?

    error.message
  end

  def rollback_depreciation_side_effects
    return unless @voucher.source_type == 'Erp::Depreciation'

    Erp::DepreciationService.new(Current.account, current_user).rollback_voucher!(@voucher)
  end

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

  # 追加挂载，不动已传的（整组替换会把历史附件 purge 掉）。删某一张走 detach_document。
  def attach_staged_documents
    ids = params.dig(:voucher, :documents)
    @voucher.documents.attach(ids) if ids.present?
  end

  def check_authorization
    authorize(Erp::Voucher)
  end

  def voucher_params
    params.require(:voucher).permit(
      :voucher_date, :summary, :remark, :attachment_count,
      { documents: [] },
      lines_attributes: [
        :id, :ledger_account_id, :direction, :summary, :amount_micros, :currency, :exchange_rate, :position,
        :crm_customer_id, :mes_supplier_id, :crm_sales_order_id, :department_id, :member_id,
        :cash_flow_item, :_destroy
      ]
    )
  end
end
