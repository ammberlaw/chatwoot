class Api::V1::Accounts::Mes::BomsController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  # attach / detach 也要取单：漏了它俩 @bom 是 nil，两个接口一直 500——
  # 生产任务单上「删掉这张图」从来没成功过（2026-10-10 查附件丢失时发现）。
  before_action :fetch_bom, only: [:show, :update, :destroy, :release, :attach, :detach]
  # 谁制单谁改（管理员可代改）——BOM 的 owner 就是工程/PMC 制单人。
  # 挂附件/删附件同样是改单，一并收口。
  before_action -> { ensure_owner_or_admin!(@bom, '生产任务单') }, only: [:update, :destroy, :attach, :detach]

  # 按明细筛三列（物料编码/名称/规格）用：任一行命中即留下这张任务单。
  ITEM_MATCH_SQL = lambda { |cond|
    <<~SQL.squish
      EXISTS (SELECT 1 FROM mes_bom_items bi
               WHERE bi.bom_id = mes_boms.id AND (#{cond}))
    SQL
  }

  # 表头上每列各自的筛选（对标金蝶的漏斗）。列 → 查询条件的映射放在后端，
  # 因为列表是分页的：前端只过滤本页，第 2 页往后的命中就全看不见了。
  COLUMN_FILTERS = {
    no: ->(scope, v) { scope.where('mes_boms.bom_no ILIKE :t OR mes_boms.doc_no ILIKE :t', t: "%#{v}%") },
    model: lambda { |scope, v|
      scope.left_joins(:crm_product)
           .where('mes_boms.model ILIKE :t OR crm_products.name ILIKE :t', t: "%#{v}%")
    },
    product_code: ->(scope, v) { scope.where('mes_boms.product_code ILIKE ?', "%#{v}%") },
    customer_name: ->(scope, v) { scope.where('mes_boms.customer_name ILIKE ?', "%#{v}%") },
    owner_id: ->(scope, v) { scope.where(owner_id: v) },
    sales_owner_id: ->(scope, v) { scope.where(sales_owner_id: v) },
    status: ->(scope, v) { scope.where(status: v) },
    # 按明细视图的三列：一张任务单只要有一行料对上就留下——
    # 「哪几张单用了这颗料」正是采购/PMC 查这三列的目的。
    item_code: ->(scope, v) { scope.where(ITEM_MATCH_SQL.call('bi.material_no ILIKE :t'), t: "%#{v}%") },
    item_name: ->(scope, v) { scope.where(ITEM_MATCH_SQL.call('bi.material_name ILIKE :t'), t: "%#{v}%") },
    item_spec: ->(scope, v) { scope.where(ITEM_MATCH_SQL.call('bi.specification ILIKE :t'), t: "%#{v}%") }
  }.freeze

  def index
    scope = apply_column_filters(scoped_by_bom_visibility(Current.account.mes_boms))
    # 产线筛选放在最后：要先数出「本次筛选条件下、产线为空因而被产线分流隐藏」的条数。
    @hidden_no_line = hidden_without_product_line(scope)
    scope = scoped_by_product_line(scope)
    @boms_count = scope.count
    # 预加载序列化要用的：用料行、成品、以及挂在本 BOM 上的生产订单
    # （成本那段要拿它的「本单采购价」，不预加载就是每行一次查询）。
    @boms = scope.includes(:bom_items, :crm_product, :production_orders)
                 .order(created_at: :desc, id: :desc).page(page_param).per(RESULTS_PER_PAGE)
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
    # 下发态 BOM 改用料 → 记一条变更单并通知已参与的下游部门（草稿编辑不留痕）。
    was_released = @bom.released?
    before = was_released ? @bom.items_snapshot : nil
    @bom.update!(bom_params)
    attach_staged_blobs
    record_bom_revision(before) if was_released
    render 'api/v1/accounts/mes/boms/show'
  end

  # 这颗料被**别的在产订单**排掉了多少。实时库存写着 100 不代表这 100 能用，
  # 工程照着库存决定不采购、到领料那天就缺货（用户点名要在实时库存旁边提示）。
  # bom_id 传当前这张任务单，把它自己排除掉——「其他订单占用」不该把自己算进去。
  def material_commitments
    map = Mes::MaterialCommitment.by_material_no(Current.account, exclude_bom_id: params[:bom_id])
    render json: { payload: map.transform_values(&:to_s) }
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

  # kind = images（结构图/样品）| logos（客户 logo）| files（附件），默认 files。
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

  # 删单：只许删**草稿**，且**没有任何生产订单挂着它**。
  # 两道闸都是硬的：mes_production_orders.bom_id 是 on_delete: nullify，删掉一张被挂着的
  # BOM 不会报错——订单会悄悄失去用料，谁都看不出来发生过什么。已下发的更不能删。
  def destroy
    blocker = destroy_blocker
    return render json: { error: blocker }, status: :unprocessable_entity if blocker

    @bom.destroy!
    head :ok
  end

  private

  def destroy_blocker
    return '只有草稿状态的生产任务单可以删除；已下发的请改用修订或作废' unless @bom.status == 'DRAFT'

    linked = Current.account.mes_production_orders.where(bom_id: @bom.id)
    return nil if linked.empty?

    "这张生产任务单已被 #{linked.pluck(:order_no).join('、')} 挂着，删了那些订单就没有用料了；请先在订单上解除关联"
  end

  def fetch_bom
    @bom = Current.account.mes_boms.find(params[:id])
  end

  def check_authorization
    authorize(Mes::Bom)
  end

  ATTACH_COLLECTIONS = { 'images' => :images, 'files' => :files, 'logos' => :logos }.freeze

  def attach_collection
    ATTACH_COLLECTIONS[params[:kind]] || :files
  end

  # 建单/编辑时把已暂存的 blob signed_id 追加挂载（append 语义，不覆盖已有附件）。
  #
  # ⚠️ 这三个集合**绝不能**进 bom_params：has_many_attached 的赋值是整组替换
  # （Rails 把没列进来的旧附件直接 purge 掉）。前端每次只发新暂存的那几个、
  # 没加新图时发空数组——进了 update! 就等于把这张单历史上所有的图清空。
  # 2026-10-10 采购反馈「以前生产单插的图现在都没了」就是这么丢的。
  def attach_staged_blobs
    images = params.dig(:bom, :images)
    files = params.dig(:bom, :files)
    logos = params.dig(:bom, :logos)
    @bom.images.attach(images) if images.present?
    @bom.files.attach(files) if files.present?
    @bom.logos.attach(logos) if logos.present?
  end

  # 建单时选了「关联生产订单」：下发的 BOM 保存后直接挂到该订单（订单进 BOM_READY、
  # 通知业务员二次确认）；存草稿不挂（下发后再从订单页挂）。BOM 归属业务员为空时随订单补齐。
  # 下发态 BOM 编辑后：对比用料快照，有实质变更则落一条变更单，并通知本 BOM 所挂
  # 各在产订单「已参与过的下游部门」+ 业务员（§ BOM 变更同步）。无变更不记、不扰。
  def record_bom_revision(before)
    changes = Mes::Bom.diff_items(before, @bom.reload.items_snapshot)
    return if changes.blank?

    rev_no = (@bom.bom_revisions.maximum(:rev_no) || 0) + 1
    @bom.bom_revisions.create!(
      account_id: @bom.account_id, rev_no: rev_no, changed_by_id: current_user.id,
      reason: params.dig(:bom, :change_reason).presence, diff: changes
    )
    summary = Mes::Bom.diff_summary(changes)
    @bom.production_orders.where.not(stage: 'SHIPPED').where.not(status: 'CANCELLED').each do |order|
      sync_order_after_revision(order, summary, rev_no)
    end
  end

  # 用料变了，受影响的订单要做两件事：作废业务上一轮的确认（不然不用重新点头就能下发
  # 采购，这道闸形同虚设，见 ProductionOrder#confirm_bom!），再通知已参与的下游部门。
  def sync_order_after_revision(order, summary, rev_no)
    order.reset_bom_confirmation!(actor: current_user)
    order.notify_bom_revised(summary, rev_no, actor: current_user)
  end

  def attach_to_order_if_requested
    order_id = params.require(:bom)[:production_order_id]
    return if order_id.blank? || @bom.status != 'RELEASED'

    order = Current.account.mes_production_orders.find(order_id)
    @bom.update!(sales_owner_id: order.owner_id) if @bom.sales_owner_id.blank?
    order.attach_bom!(@bom, actor: current_user)
  end

  def apply_column_filters(scope)
    scope = scope.where(crm_product_id: params[:crm_product_id]) if params[:crm_product_id].present?
    # 顶部搜索框写着「单号 / 投单单号」，就得两个都搜。原来只搜 bom_no，
    # 而列表主显示的恰恰是投单单号（doc_no，纸质单全程认的那个号）——
    # 照着单子上的号来搜一条都出不来。与表头 no 那一列同口径。
    scope = scope.where('bom_no ILIKE :t OR doc_no ILIKE :t', t: "%#{params[:q].to_s.strip}%") if params[:q].present?
    scope = date_filtered(scope)
    COLUMN_FILTERS.each do |param, apply|
      value = params[param]
      scope = apply.call(scope, value.to_s.strip) if value.present?
    end
    scope
  end

  # 投单日期区间：单边留空＝只卡一头。没填投单日期的老单回落到建单日期，
  # 否则按日期一筛，历史单整批消失。
  DATE_SQL = 'COALESCE(mes_boms.submit_date, mes_boms.created_at::date)'.freeze

  def date_filtered(scope)
    scope = scope.where("#{DATE_SQL} >= ?", params[:submit_from]) if params[:submit_from].present?
    scope = scope.where("#{DATE_SQL} <= ?", params[:submit_to]) if params[:submit_to].present?
    scope
  end

  def bom_params
    params.require(:bom).permit(
      :crm_product_id, :base_qty, :unit, :estimated_lead_days, :is_active, :is_default, :owner_id, :sales_owner_id, :product_line, :status,
      :remark, :combo_note,
      # 单号允许手工填（两账并行期要对上金蝶的号）。**只在新建时放行**——
      # 改已生效单据的号会让纸质单、下游单据和 ERP 全部对不上。留空则自动生成。
      *(action_name == 'create' ? [:bom_no] : []),
      :submit_date, :doc_no, :customer_name, :model, :product_code, :order_qty, :bare_color, :case_color,
      :purchasing_days, :material_inbound_days, :picking_days, :production_days, :fg_inbound_days,
      bom_items_attributes: [:id, :mes_material_id, :material_no, :material_name, :specification, :qty, :unit, :suggested_purchase_qty,
                             :remark, :purchase_note, :production_note, :category, :crm_product_aux_attribute_id,
                             # 卡点：这颗料为什么还没下采购单（见 Mes::BomItem::BLOCKER_LABELS）
                             :blocker_kind, :blocker_note, :blocker_owner_id, :_destroy]
    )
  end
end
