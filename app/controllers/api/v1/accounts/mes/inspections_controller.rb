class Api::V1::Accounts::Mes::InspectionsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization

  def index
    scope = scoped_by_order_owner(scoped_by_product_line(Current.account.mes_inspections))
    scope = apply_search(apply_filters(scope), params[:q])
    @inspections_count = scope.count
    @inspections = scope.order(inspected_at: :desc, id: :desc).page(page_param).per(per_page_param)
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

  # 录错了自己改（同删除，本人或管理员）。附件走 stage_blob 追加，不整组替换——
  # has_many_attached 写进 strong params 会把历史附件 purge 掉。
  def update
    @inspection = Current.account.mes_inspections.find(params[:id])
    ensure_owner_or_admin!(@inspection, '质检记录', :inspector_id)
    return if performed?

    @inspection.update!(inspection_params)
    attach_staged_blobs
    render 'api/v1/accounts/mes/inspections/show'
  end

  def destroy
    inspection = Current.account.mes_inspections.find(params[:id])
    ensure_owner_or_admin!(inspection, '质检记录', :inspector_id)
    return if performed?

    inspection.destroy!
    head :ok
  end

  private

  # 表头逐列筛选，命名与原料入库一致（col_* + COLUMN_LIKE_FILTERS）。
  # 「对象」一列在界面上是工单号/物料名/成品名三选一显示，所以要三张表都匹；
  # 用子查询不用 join——join 会让同时命中物料和成品的记录冒出两行。
  COLUMN_LIKE_FILTERS = {
    col_object: lambda { |scope, v|
      like = "%#{v}%"
      orders = Mes::ProductionOrder.where('order_no ILIKE :q OR product_name ILIKE :q', q: like).select(:id)
      materials = Mes::Material.where('name ILIKE :q OR material_no ILIKE :q', q: like).select(:id)
      products = Crm::Product.where('name ILIKE :q OR sku ILIKE :q', q: like).select(:id)
      scope.where(production_order_id: orders)
           .or(scope.where(mes_material_id: materials))
           .or(scope.where(crm_product_id: products))
    },
    col_owner: lambda { |scope, v|
      scope.where(production_order_id: Mes::ProductionOrder.joins(:owner)
                                                           .where('users.name ILIKE ?', "%#{v}%").select(:id))
    },
    col_defect: ->(scope, v) { scope.where('mes_inspections.defect_reason ILIKE ?', "%#{v}%") },
    col_inspector: lambda { |scope, v|
      scope.where(inspector_id: User.where('users.name ILIKE ?', "%#{v}%").select(:id))
    }
  }.freeze

  def apply_filters(scope)
    %i[kind result production_order_id].each do |key|
      scope = scope.where(key => params[key]) if params[key].present?
    end
    scope = apply_column_filters(scope)
    scope = scope.where(inspected_at: params[:from].to_date.beginning_of_day..) if params[:from].present?
    scope = scope.where(inspected_at: ..params[:to].to_date.end_of_day) if params[:to].present?
    scope
  end

  def apply_column_filters(scope)
    COLUMN_LIKE_FILTERS.each do |param, apply|
      scope = apply.call(scope, params[param].to_s.strip) if params[param].present?
    end
    scope
  end

  # 质检翻记录找的是「哪张单、哪个产品、什么不良」。
  def apply_search(scope, raw)
    q = raw.to_s.strip
    return scope if q.blank?

    like = "%#{q}%"
    orders = Current.account.mes_production_orders
                    .where('order_no ILIKE :q OR product_name ILIKE :q', q: like).select(:id)
    scope.where(production_order_id: orders)
         .or(scope.where('mes_inspections.defect_reason ILIKE :q', q: like))
  end

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
