class Api::V1::Accounts::Mes::InspectionsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_inspections))
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    scope = scope.where(result: params[:result]) if params[:result].present?
    scope = scope.where(production_order_id: params[:production_order_id]) if params[:production_order_id].present?
    @inspections_count = scope.count
    @inspections = scope.order(inspected_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
  end

  def create
    @inspection = Current.account.mes_inspections.create!(
      inspection_params.merge(inspector_id: inspection_params[:inspector_id] || current_user.id)
    )
    attach_staged_blobs
    render 'api/v1/accounts/mes/inspections/show'
  end

  # 录检验前先把文件暂存为 blob，拿到 signed_id，录入时通过 videos/photos/files 一并挂载。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  def destroy
    inspection = Current.account.mes_inspections.find(params[:id])
    ensure_owner_or_admin!(inspection, '质检记录', :inspector_id)
    return if performed?

    inspection.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(Mes::Inspection)
  end

  # 录入时把已暂存的 blob signed_id 追加挂载（检测视频 / 照片 / 附件）。
  def attach_staged_blobs
    %i[videos photos files].each do |kind|
      ids = params.dig(:inspection, kind)
      @inspection.public_send(kind).attach(ids) if ids.present?
    end
  end

  def inspection_params
    params.require(:inspection).permit(
      :kind, :item_type, :mes_material_id, :crm_product_id, :production_order_id, :purchase_order_id,
      :inspected_qty, :passed_qty, :failed_qty, :result, :defect_reason, :need_rework, :inspector_id, :inspected_at, :remark
    )
  end
end
