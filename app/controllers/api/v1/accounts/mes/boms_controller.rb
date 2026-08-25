class Api::V1::Accounts::Mes::BomsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_bom, only: [:show, :update, :destroy, :release]

  def index
    scope = scoped_by_bom_visibility(scoped_by_product_line(Current.account.mes_boms))
    scope = scope.where(crm_product_id: params[:crm_product_id]) if params[:crm_product_id].present?
    scope = scope.where('bom_no ILIKE :t', t: "%#{params[:q].strip}%") if params[:q].present?
    @boms_count = scope.count
    @boms = scope.order(created_at: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @bom = Current.account.mes_boms.new(bom_params)
    @bom.owner_id ||= current_user.id # 负责人默认=起草人（当前账号）
    @bom.fallback_product_line = current_product_line
    @bom.save!
    attach_staged_blobs
    attach_to_order_if_requested
    render 'api/v1/accounts/mes/boms/show'
  end

  def update
    @bom.update!(bom_params)
    attach_staged_blobs
    render 'api/v1/accounts/mes/boms/show'
  end

  # 建单前把文件暂存为 blob，拿到 signed_id，建单/编辑时通过 images/files 一并挂载。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  # kind = images（结构图/样品）| files（附件），默认 files。
  def attach
    @bom.public_send(attach_collection).attach(params[:files])
    render 'api/v1/accounts/mes/boms/show'
  end

  def detach
    @bom.public_send(attach_collection).find(params[:attachment_id]).purge
    render 'api/v1/accounts/mes/boms/show'
  end

  # 下发草稿 BOM → 正式生效，可被生产订单挂用。
  def release
    @bom.update!(status: 'RELEASED')
    render 'api/v1/accounts/mes/boms/show'
  end

  def destroy
    @bom.destroy!
    head :ok
  end

  private

  def fetch_bom
    @bom = Current.account.mes_boms.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Bom)
  end

  ATTACH_COLLECTIONS = { 'images' => :images, 'files' => :files }.freeze

  def attach_collection
    ATTACH_COLLECTIONS[params[:kind]] || :files
  end

  # 建单/编辑时把已暂存的 blob signed_id 追加挂载（append 语义，不覆盖已有附件）。
  def attach_staged_blobs
    images = params.dig(:bom, :images)
    files = params.dig(:bom, :files)
    @bom.images.attach(images) if images.present?
    @bom.files.attach(files) if files.present?
  end

  # 建单时选了「关联生产订单」：下发的 BOM 保存后直接挂到该订单（订单进 BOM_READY、
  # 通知业务员二次确认）；存草稿不挂（下发后再从订单页挂）。BOM 归属业务员为空时随订单补齐。
  def attach_to_order_if_requested
    order_id = params.require(:bom)[:production_order_id]
    return if order_id.blank? || @bom.status != 'RELEASED'

    order = Current.account.mes_production_orders.find(order_id)
    @bom.update!(sales_owner_id: order.owner_id) if @bom.sales_owner_id.blank?
    order.attach_bom!(@bom, actor: current_user)
  end

  def bom_params
    params.require(:bom).permit(
      :crm_product_id, :base_qty, :unit, :estimated_lead_days, :is_active, :is_default, :owner_id, :sales_owner_id, :remark, :product_line, :status,
      :submit_date, :doc_no, :customer_name, :model, :product_code, :order_qty, :bare_color, :case_color,
      :purchasing_days, :material_inbound_days, :picking_days, :production_days, :fg_inbound_days,
      bom_items_attributes: [:id, :mes_material_id, :material_no, :material_name, :specification, :qty, :unit, :remark, :category, :_destroy]
    )
  end
end
