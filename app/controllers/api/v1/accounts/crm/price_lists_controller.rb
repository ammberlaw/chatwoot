# 核价表（内部报价单）：主管/财务按版本维护，业务员只读已发布/历史版本。
# 明细随版本整表提交（业务上就是「改完一张表再发一版」，不做逐行接口）。
class Api::V1::Accounts::Crm::PriceListsController < Api::V1::Accounts::Crm::BaseController
  SEARCH_LIMIT = 60
  # 财务身份常无 crm_role，会被 CRM 总门禁拦掉；与备用金台账同款跳过总门禁，
  # 可见与写权限在本控制器内把关。
  skip_before_action :ensure_crm_access
  before_action :ensure_visible!
  before_action :ensure_writable!,
                only: %i[create update destroy publish duplicate import upload_image remove_image image_from_doc]
  before_action :fetch_list,
                only: %i[show update destroy publish duplicate export_pdf upload_image remove_image image_from_doc diff]

  def index
    scope = visible_lists
    scope = scope.for_line(params[:product_line]) if params[:product_line].present?
    @price_lists = scope.newest_first
    # 产品线清单给前端做切换（一条产品线一张表，各自独立走版本）。
    @product_lines = ordered_product_lines(visible_lists.distinct.order(:product_line).pluck(:product_line))
    @can_manage = can_write?
  end

  def show
    @can_manage = can_write?
  end

  def create
    @price_list = Current.account.crm_price_lists.new(list_params.merge(creator_id: Current.user&.id))
    @price_list.save!
    replace_items(@price_list)
    render :show
  end

  def update
    @price_list.update!(list_params)
    replace_items(@price_list) if params[:price_list].key?(:items)
    render :show
  end

  def destroy
    return render json: { error: '已发布的版本不能删除，可先发新版再归档' }, status: :unprocessable_entity if @price_list.status == 'PUBLISHED'

    @price_list.destroy!
    head :ok
  end

  # 发布：本版生效，其余已发布版自动归档。
  def publish
    @price_list.publish!(Current.user)
    render :show
  end

  # 复制成草稿：调价时不用重录二十几行。
  def duplicate
    @price_list = @price_list.duplicate_as_draft(Current.user)
    render :show
  end

  # 从公司现成的核价 Excel 建表：一个 sheet 建一条产品线的草稿（列按表头自动识别）。
  def import
    return render json: { error: '请选择 .xlsx 文件' }, status: :unprocessable_entity if params[:file].blank?

    results = Crm::PriceListImporter.new(account: Current.account, user: Current.user, file: params[:file]).call
    return render json: { error: '没读到可导入的表格，请确认表头在前几行' }, status: :unprocessable_entity if results.empty?

    render json: { imported: results.map { |r| { id: r.price_list.id, product_line: r.price_list.product_line, rows: r.rows } } }
  rescue StandardError => e
    Rails.logger.warn("[Crm::PriceListImport] failed: #{e.class}: #{e.message}")
    render json: { error: "导入失败：#{e.message}" }, status: :unprocessable_entity
  end

  # 跨产品线搜型号：业务员知道客户要哪个型号，但未必知道它归在哪条产品线。
  # 只搜文本列（型号/名称/参数），价格列搜数字没意义。
  def search
    q = params[:q].to_s.strip
    return render json: { payload: [] } if q.length < 2

    lists = visible_lists.where.not(status: 'DRAFT').includes(:items).newest_first
    render json: { payload: Crm::PriceListSearch.new(lists: lists, query: q, limit: SEARCH_LIMIT).call }
  end

  # 与上一版对比：涨了/降了/新增/下架，主管发布前自查用。
  def diff
    previous = @price_list.account.crm_price_lists.for_line(@price_list.product_line)
                          .where.not(id: @price_list.id)
                          .where(effective_on: ..@price_list.effective_on).newest_first.first
    return render json: { error: '这是该产品线的第一版，没有可对比的版本' }, status: :unprocessable_entity if previous.nil?

    render json: Crm::PriceListDiff.new(current: @price_list, previous: previous).call
  end

  # 公司文档里的图片清单：产品图基本都在「设计资料」板块，挑现成的比重新上传省事。
  # 按板块分组给前端做切换，默认停在设计资料。
  def doc_images
    picker = Crm::DocImagePicker.new(account: Current.account, user: current_user,
                                     section_id: params[:section_id], query: params[:q])
    render json: { sections: picker.sections, payload: picker.images }
  end

  # 从公司文档挑一张挂到某行。复制一份 blob 而不是共用——共用的话这边删图会把文档里的原文件一起删掉。
  def image_from_doc
    item = @price_list.items.find(params[:item_id])
    att = Crm::DocImagePicker.new(account: Current.account, user: current_user)
                             .attachment(params[:attachment_id])
    return render json: { error: '找不到这张图片' }, status: :not_found if att.nil?

    # 用 blob.open 流式复制，别整个读进内存（大图 + 并发会把内存吃穿）。
    att.blob.open do |file|
      item.image.attach(io: file, filename: att.blob.filename.to_s, content_type: att.blob.content_type)
    end
    render json: { id: item.id, image_url: image_url_for(item) }
  end

  # 某一行挂产品图（核价表靠图认产品，型号名看不出长什么样）。
  def upload_image
    item = @price_list.items.find(params[:item_id])
    return render json: { error: '请选择图片' }, status: :unprocessable_entity if params[:file].blank?

    item.image.attach(params[:file])
    render json: { id: item.id, image_url: image_url_for(item) }
  end

  def remove_image
    item = @price_list.items.find(params[:item_id])
    item.image.purge
    head :ok
  end

  # 导出 PDF：版式还原公司原始核价表（表头备注 / 阶梯价 / 报价规则 / 落款）。
  def export_pdf
    pdf = Crm::PriceListPdf.new(price_list: @price_list).render
    send_data pdf, filename: "#{@price_list.export_basename}.pdf", type: 'application/pdf', disposition: 'attachment'
  rescue Mes::GotenbergClient::ConversionError => e
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def image_url_for(item)
    Rails.application.routes.url_helpers.rails_blob_path(item.image, only_path: true)
  end

  # 平板是主力产品线，置顶；其余按名称排。也是进页面时的默认产品线。
  PINNED_LINE = '平板电脑'.freeze

  def ordered_product_lines(lines)
    pinned, rest = lines.partition { |l| l == PINNED_LINE }
    pinned + rest
  end

  # 维护权：管理员 / 副管理员 / 财务 / 业务部门负责人。
  def can_write?
    au = Current.account_user
    return false if au.blank?

    au.administrator? || au.crm_deputy_admin? || au.crm_finance? || au.led_department_ids.any?
  end

  # 业务员看不到草稿——没发布的价不能拿去报。
  def visible_lists
    return Current.account.crm_price_lists if can_write?

    Current.account.crm_price_lists.where.not(status: 'DRAFT')
  end

  def ensure_visible!
    return if can_write? || Current.account_user&.can_access_crm?

    render json: { error: '无权查看核价表' }, status: :forbidden
  end

  def ensure_writable!
    return if can_write?

    render json: { error: '仅主管、财务与管理员可维护核价表' }, status: :forbidden
  end

  def fetch_list
    @price_list = visible_lists.includes(:creator, :published_by, :items).find(params[:id])
  end

  # 明细按 id 增/改/删——不能整表先删后建，那样会把每行挂着的产品图一起删掉。
  def replace_items(list)
    kept = Array(params.dig(:price_list, :items)).each_with_index.filter_map do |raw, i|
      upsert_item(list, raw.permit(:id, :remark, values: []).to_h, i)
    end
    list.items.where.not(id: kept).destroy_all
    list.items.reload
  end

  # 返回保留下来的 item id；整行空的跳过（编辑器里常留空行）。
  def upsert_item(list, attrs, position)
    cells = Array(attrs['values']).map { |v| v.to_s.strip }
    return nil if cells.all?(&:blank?)

    item = list.items.find_by(id: attrs['id']) || list.items.new(account_id: list.account_id)
    item.update!(position: position, values: cells, remark: attrs['remark'])
    item.id
  end

  def list_params
    params.require(:price_list).permit(:title, :product_line, :effective_on, :currency,
                                       :header_note, :rules_note, :footer_name,
                                       columns: [:label, :type])
  end
end
