class Api::V1::Accounts::Mes::ProductionOrdersController < Api::V1::Accounts::Mes::BaseController
  before_action :check_authorization
  before_action :fetch_production_order,
                only: [:show, :update, :destroy, :attach, :detach, :audits, :forward, :attach_bom, :detach_bom, :revert_to_bom_ready, :release_purchasing, :skip_purchasing, :requirement, :handoff,
                       :issue_plan, :acknowledge, :reject, :submit_approval, :approve, :deny, :set_product_code, :mark_outsourced,
                       :return_to_sales, :resolve_sales_return, :confirm_bom]
  before_action :ensure_editable!, only: [:update, :attach, :detach]
  before_action :ensure_deletable!, only: [:destroy]

  COLUMN_FILTERS = { stage: :stage, status: :status, crm_sales_order_id: :crm_sales_order_id, owner_id: :owner_id }.freeze

  # 表头上每列各自的筛选（对标金蝶的漏斗）。放后端是因为列表分页：
  # 前端只过滤本页，第 2 页往后的命中就全看不见了。
  COLUMN_LIKE_FILTERS = {
    col_no: ->(scope, v) { scope.where('mes_production_orders.order_no ILIKE ?', "%#{v}%") },
    col_model: lambda { |scope, v|
      scope.left_joins(:crm_product)
           .where('mes_production_orders.product_name ILIKE :t OR crm_products.name ILIKE :t', t: "%#{v}%")
    },
    col_sku: ->(scope, v) { scope.left_joins(:crm_product).where('crm_products.sku ILIKE ?', "%#{v}%") },
    col_spec: ->(scope, v) { scope.left_joins(:crm_product).where('crm_products.specification ILIKE ?', "%#{v}%") },
    # 走子查询不走 join：crm_sales_orders 上也有 owner_id，join 进来后
    # 外层 scoped_by_owner 的 where(owner_id:) 就成了歧义列，整个列表 500。
    col_sales_order: lambda { |scope, v|
      scope.where(crm_sales_order_id: Crm::SalesOrder.where('crm_sales_orders.order_no ILIKE ?', "%#{v}%").select(:id))
    },
    col_remark: ->(scope, v) { scope.where('mes_production_orders.remark ILIKE ?', "%#{v}%") }
  }.freeze

  # 交期区间：单边留空＝只卡一头。
  DUE_SQL = 'mes_production_orders.delivery_date'.freeze

  # 列表分片 _mes_production_order 逐行解引用的关联，一次预加载掉。
  LIST_EAGER_LOADS = [
    :owner, :outsource_supplier, :bom_confirmed_by, :gm, :stage_ack_by,
    # manager（审批人名）与 bom.bom_revisions（BOM 变更记录）分片里逐行要，
    # 漏了就是一页一百行各查一次库。
    :manager, :crm_customer, :crm_product, :crm_sales_order, :stage_events, :purchase_orders,
    # blocked_bom_items：阶段格旁边的卡点标签逐行要（已带 blocker_owner，提示里要写「等谁」）。
    { bom: [:bom_revisions, { blocked_bom_items: :blocker_owner }] },
    { images_attachments: :blob, files_attachments: :blob }
  ].freeze

  def index
    scope = scoped_by_owner(Current.account.mes_production_orders.visible_to(current_user))
    scope = apply_list_scope(scope)
    COLUMN_FILTERS.each do |param, column|
      scope = scope.where(column => params[param]) if params[param].present?
    end
    scope = apply_column_filters(scope)
    scope = apply_search(scope)
    # 产线筛选放在最后：要先数出「本次筛选条件下、产线为空因而被产线分流隐藏」的条数。
    @hidden_no_line = hidden_without_product_line(scope)
    scope = scoped_by_product_line(scope)
    @production_orders_count = scope.count
    # 「业务员」下拉的候选：实际当过订单归属人的那些人。
    # 前端按 crm_role 过滤掉非销售条线（生产/仓管/采购混在里面没法翻），但光按角色会漏——
    # 生产上「陈云钢」没有 crm_role、名下却有 2 张订单，一刀切他的单就筛不出来了。
    # 这里报出真实存在的归属人，前端拿它兜底。
    @owner_ids = scope.distinct.pluck(:owner_id).compact
    # 列表分片逐行取这些关联，不预加载就是每行一次查库（dev 的 Bullet 直接抛异常打断页面）。
    @production_orders = scope.includes(LIST_EAGER_LOADS).order(created_at: :desc, id: :desc).page(page_param).per(per_page_param)
    # 已完工入库量整批查一次；逐行算就是一页几百条 SQL（成品入库页一次拉 500 张订单）。
    @fg_inbound_qty_by_order = Mes::ProductionOrder.bulk_fg_inbound_qty(Current.account, @production_orders.map(&:id))
    # 领料状态同理：列表要显示领没领过料，整批查一次。
    @issued_counts_by_order = Mes::ProductionOrder.bulk_issued_counts(Current.account, @production_orders.map(&:id))
    # 组装齐 / 包装齐：业务在列表上一眼看出能不能开工、能不能装箱（原来要点进缺料清单数）。
    @kit_readiness = Mes::KitReadiness.bulk(Current.account, @production_orders.to_a)
    # 采购单的「关联生产订单」下拉要把料已下满的单拿掉，这个判断要展开 BOM，只在它要的时候算。
    return unless boolean_param(:with_purchasing_complete)

    @purchasing_complete_ids = Mes::ProductionOrder.bulk_purchasing_complete(Current.account, @production_orders.to_a)
    # 没下满的那些要在下拉里标「已下 N 张 · 还差 M 项料」，否则看不出下过没有、容易重复下单。
    @purchase_overview = Mes::ProductionOrder.bulk_purchase_overview(Current.account, @production_orders.to_a)
  end

  def show; end

  def create
    @production_order = Current.account.mes_production_orders.new(
      production_order_params.merge(owner_id: production_order_params[:owner_id] || current_user.id)
    )
    return unless apply_sales_user_limits!(@production_order)

    # 同一张销售订单的同一个成品，手工建单也不许重复——生产上出现过同一张 PI 隔三分钟
    # 建出两张一模一样的工单（单号手填，一张 -01 一张 -001），下游采购照着两张单各下一次料。
    # 一键转单（convert）早就按「销售订单 + 产品」做了幂等，这里补上手工入口的同一道闸。
    dup = duplicate_order_for(@production_order)
    if dup
      return render json: { error: "销售订单 #{dup.crm_sales_order&.order_no} 的这个成品已经建过生产订单 #{dup.order_no}，不要重复建单" },
                    status: :unprocessable_entity
    end

    @production_order.fallback_product_line = current_product_line
    @production_order.save!
    # submit=true：建单即提交审批（业务员点「提交审批」）；否则留草稿。
    @production_order.submit_for_approval!(current_user) if boolean_param(:submit)
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 暂存文件为 ActiveStorage blob（建单前即可上传）：返回 signed_id，建单时通过 images/files 挂载。
  def stage_blob
    file = params[:file]
    return render json: { error: '未收到文件' }, status: :unprocessable_entity if file.blank?

    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.open, filename: file.original_filename, content_type: file.content_type
    )
    render json: { signed_id: blob.signed_id, filename: blob.filename.to_s, url: rails_blob_path(blob, only_path: true) }
  end

  # 从销售订单一键转生产订单（脊柱起点）。**每行明细各转一张**——生产脊柱按成品走，
  # 一张生产订单只做一个成品，所以一张多型号的销售订单对应多张生产订单（都挂回同一张销售单）。
  #
  # 幂等按「销售订单 + 产品」判，不是整单判：
  #   连点两下、前后端重试都不会重复建；订单后来补了一行明细，再转一次只会补那一行。
  #   （同一张订单同一个产品拆成两行的情况生产上没有，真出现时按一张单转，数量业务自行合并。）
  #
  # 审批口径按能力分（业务员一键转单不是绕审批的口子）：
  #   有 :order 能力（PMC/管理员）→ 直接 APPROVED 进生产流转；
  #   业务员等 CRM 角色 → 落草稿并提交审批，主管/总经理审完才生效。
  def convert
    sales_order = Current.account.crm_sales_orders.find(params[:crm_sales_order_id])
    # 审核闸：销售订单审过了才能往下游推（用户原话「转 mes 或 erp 时需要被审核才可以推送」）。
    # 存量单迁移时统一置 APPROVED，闸只对新单生效。
    unless sales_order.pushable?
      return render json: { error: "销售订单 #{sales_order.order_no} #{sales_order.approval_label}，审核通过后才能转生产订单" },
                    status: :unprocessable_entity
    end

    # 转单时勾的「订单金额已含税」写回销售订单（出库收入凭证按它拆行，见 ERP_SPEC §8.2bis）。
    # 订单类型一并写回（2026-10-22）：以前转单选的类型只管这一次，订单上那栏照旧空着，
    # 下次转同一张单还得再选一遍。既然转单的人已经判断过这单该走哪条线，就以他选的为准。
    tax = params[:amount_includes_tax]
    writeback = { order_kind: 'CUSTOM', updated_at: Time.current }
    writeback[:amount_includes_tax] = ActiveModel::Type::Boolean.new.cast(tax) unless tax.nil?
    sales_order.update_columns(writeback) # rubocop:disable Rails/SkipsModelValidations
    rows = convert_rows
    return render json: { error: '请至少选择一行明细' }, status: :unprocessable_entity if rows.empty?

    converted = converted_product_nos(sales_order)
    pending = rows.reject { |row| converted.key?(row[:crm_product_id]) }
    if pending.empty?
      return render json: { error: "所选明细都已生成生产订单（#{converted.values.uniq.join('、')}），不能重复转单" },
                    status: :unprocessable_entity
    end

    orders = ActiveRecord::Base.transaction { pending.map { |row| save_converted_order(sales_order, row) } }
    # 人工点中的产品落回明细 + 别名记忆，下次不用再点（放事务外：记忆失败不该回滚已建的单）。
    Crm::ConvertChoiceRecorder.new(sales_order).call(rows)
    render json: { order_nos: orders.map(&:order_no), skipped: rows.size - pending.size }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 按 BOM 推料（生产领料预填）：默认只推**整机生产物料**（包装物料未到不挡开产，
  # 打包时再另领）；传 category=PACKAGING 可单推包装料。
  def requirement
    category = params[:category].presence || 'MACHINE'
    rows = @production_order.material_requirements(category: category)
    # 供应商信息只对 MES 人员可见；销售等非 MES 角色隐去 mes_supplier_id（与 jbuilder 同门禁）。
    rows.each { |r| r.delete(:mes_supplier_id) } unless Current.account_user&.mes_staff?
    render json: { payload: rows }
  end

  # 生产领料计划：BOM 推料 + 每行「已领量/实时库存/待领量」。warehouse_id 传入算该仓库存。
  #
  # 不按类别过滤（传 category=MACHINE / PACKAGING 可单推一类）。
  # 原先这里和采购算料一样默认只推 MACHINE，但领料页从没给过切类别的入口，
  # 结果**包装物料根本领不出来**——一张 27 行的 BOM 只推得出 9 行组装料，
  # 另外 18 行包装料在界面上无路可走（2026-10-26 用户反馈）。
  # 领料和采购的口径本来就不同：采购关心「缺什么料会挡开产」，所以分类下单；
  # 领料关心「这张单还欠仓库多少」，已领的行 pending_qty 自然归零，推全量不会重复领。
  def issue_plan
    rows = @production_order.issue_plan(
      warehouse_id: params[:warehouse_id].presence,
      category: params[:category].presence
    )
    rows.each { |r| r.delete(:mes_supplier_id) } unless Current.account_user&.mes_staff?
    # 折算口径一并给前端摆出来：基准量和明细用量填拧了（基准量 3、明细按整单 300 填）时，
    # 倍数会变成 100，推出来的量看着像真的。把「按 N 台折算到 M 台（×K）」写在界面上，
    # 填错一眼就看得见。
    render json: { payload: rows, meta: issue_plan_meta }
  end

  # 挂工程 BOM（阶段 2）：绑 BOM + 期望交期 → 进 BOM_READY。预估完工仍按 BOM 天数自动算。
  def attach_bom
    bom = Current.account.mes_boms.find(params[:bom_id])
    @production_order.update!(delivery_date: params[:delivery_date]) if params[:delivery_date].present?
    @production_order.attach_bom!(bom)
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 业务确认用料无误：工程/PMC 做好生产任务单后要业务点头，点完才能下发采购。
  # 谁能点＝订单归属业务员本人或管理员（和改单同一口径）。
  def confirm_bom
    return render json: { error: '只有这张单的归属业务员能确认用料' }, status: :forbidden unless can_confirm_bom?

    @production_order.confirm_bom!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 工程/PMC 制单后一键下发到采购阶段（BOM_READY → PURCHASING）。
  def release_purchasing
    @production_order.release_to_purchasing!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 无需采购：料现成在库里，跳过采购直接进「原料入库」，好让领料开单（不动库存）。
  def skip_purchasing
    return render json: { error: '无权操作' }, status: :forbidden unless can_skip_purchasing?

    @production_order.skip_purchasing!(actor: current_user, reason: params[:reason].to_s.strip.presence)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 解除 BOM 关联（挂错了重挂）：清 bom_id 并退回「待工程接单」。
  def detach_bom
    @production_order.detach_bom!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 采购原料退回工程/PMC BOM（下发早了 / BOM 要改）。
  def revert_to_bom_ready
    @production_order.revert_to_bom_ready!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 工程判定为外购成品：选定产品+供应商，跳过 BOM 直接进采购（短版脊柱）。
  def mark_outsourced
    @production_order.mark_outsourced!(
      crm_product_id: params[:crm_product_id].presence,
      supplier_id: params[:mes_supplier_id].presence,
      product_name: params[:product_name].presence,
      actor: current_user
    )
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 接单：本阶段负责人（或管理员）确认接手。计时不受影响，仅定性。
  def acknowledge
    return render json: { error: '只有本阶段负责人可接单' }, status: :forbidden unless can_handle_stage?(@production_order)
    unless admin_like? || todo_list.ack_role_match?(@production_order)
      return render json: { error: "这一段归#{@production_order.ack_role_label}接单" }, status: :forbidden
    end

    @production_order.acknowledge!(current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 转给同阶段另一位负责人（工程 ↔ PMC 接力）。转出后接单状态清空，
  # 接收人那边重新出现「待我接单」。
  def handoff
    return render json: { error: '只有本阶段负责人可转交' }, status: :forbidden unless can_handle_stage?(@production_order)

    to_user = Current.account.users.find_by(id: params[:to_user_id])
    return render json: { error: '请选择要转交的负责人' }, status: :unprocessable_entity if to_user.blank?

    @production_order.handoff_stage!(actor: current_user, to_user: to_user, note: params[:note])
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 拒收打回：退回上一阶段并记原因，责任明确回上游。
  def reject
    return render json: { error: '只有本阶段负责人可拒收' }, status: :forbidden unless can_handle_stage?(@production_order)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写退回原因' }, status: :unprocessable_entity if reason.blank?

    @production_order.reject_to_previous!(actor: current_user, reason: reason)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 我的待办：当前停在「我负责的阶段」的在产订单（到岗通知的拉取面）。
  def inbox
    orders = todo_list.inbox_orders
    states = todo_list.purchase_state_map(orders)
    render json: { payload: orders.map { |po| inbox_row(po, states[po.id]) } }
  end

  # 「我现在能办的事」统一出口：六条来源一份查询，计数与列表同源（见 Mes::TodoList）。
  def todos
    render json: { meta: { count: todo_list.items.size, by_action: todo_list.counts },
                   payload: todo_list.items }
  end

  # 首页 MES 入口卡的角标：只要数字，不拉整份列表。
  # 口径必须和 inbox / approval_inbox / 出库审批三处完全一致，
  # 否则角标显示 3 条、点进去只有 2 条，业务会以为漏单。
  def todo_count
    render json: todo_list.counts
  end

  # ── 审批链：提交 → 部门主管通过/驳回 → 总经理通过/驳回 ──

  # 提交审批（草稿/被驳回 → 待部门主管）。仅创建人或管理员可提交。
  def submit_approval
    return render json: { error: '只有创建人可提交审批' }, status: :forbidden unless @production_order.owner_id == current_user.id || admin_like?

    @production_order.submit_for_approval!(current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 通过：按当前环节校验审批人（部门主管本人 / 总经理本人 / 管理员）。
  def approve
    return render json: { error: '无权审批当前环节' }, status: :forbidden unless can_approve?(@production_order)

    comment = params[:comment].to_s.strip.presence
    case @production_order.approval_status
    when 'SUBMITTED' then @production_order.manager_approve!(current_user, comment: comment)
    when 'MANAGER_APPROVED' then @production_order.gm_approve!(current_user, comment: comment)
    else return render json: { error: '当前状态无法审批' }, status: :unprocessable_entity
    end
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 驳回：退回业务员（可改后重提）。需填原因。
  def deny
    return render json: { error: '无权审批当前环节' }, status: :forbidden unless can_approve?(@production_order)

    reason = params[:reason].to_s.strip
    return render json: { error: '请填写驳回原因' }, status: :unprocessable_entity if reason.blank?

    @production_order.reject_approval!(current_user, reason: reason)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 待我确认：停在我这一级的审批单（部门主管/总经理）+ 待我二次确认 BOM 的单（业务员）。
  def approval_inbox
    base = Current.account.mes_production_orders
    scope = base.awaiting_manager_for(current_user.id)
                .or(base.awaiting_gm_for(current_user.id))

    @production_orders = scope.includes(:owner).order(submitted_at: :desc)
    @production_orders_count = @production_orders.size
    render 'api/v1/accounts/mes/production_orders/index'
  end

  # 产品编码：由工程/PMC 编写（唯一，供 ERP 共享）。策略 set_product_code? 限 bom 能力。
  def set_product_code
    @production_order.update!(product_code: params[:product_code].to_s.strip.presence)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors[:product_code].first || e.message }, status: :unprocessable_entity
  end

  # 成本导出：按月份或日期区间，一次导全月的任务单成本（汇总 + 用料明细两个页签）。
  # 财务原来一单一单导、再手工查价算成本；这里一次给全。
  def cost_export
    orders = cost_export_scope
    label = if params[:bom_id].present?
              orders.map(&:order_no).join('、')
            else
              [params[:month].presence, "#{orders.size} 张单"].compact.join(' · ')
            end
    stream = Mes::BomCostXlsxService.new(account: Current.account, orders: orders, label: label).to_stream
    send_data stream.read, filename: cost_export_filename,
                           type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  def update
    # 已下发（非草稿）订单被改 → 改完通知当前阶段的下一个流程负责人（需求：改单同步下游）。
    was_published = !@production_order.is_draft
    @production_order.assign_attributes(production_order_params)
    # 建单时的收口在改单时同样要走：否则业务员把自己的草稿从备货改回按单、
    # 顺手把销售订单关联删掉，就绕过了「业务订单必须关联销售订单」。
    return unless apply_sales_user_limits!(@production_order)

    @production_order.save!
    @production_order.notify_order_revised(actor: current_user) if was_published
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 删单：生产订单是硬删（不像销售订单进回收箱），所以先拦下游单据——
  # 删完才发现采购单、入库单成了孤儿就找不回来了。
  def destroy
    blockers = @production_order.delete_blockers
    if blockers.any?
      return render json: { error: "这张单下面已经有#{blockers.join('、')}，不能直接删。请先处理掉它们，或作废这张单。" },
                    status: :unprocessable_entity
    end

    @production_order.destroy!
    head :ok
  end

  # kind = images（产品图片）| files（附件），默认 files。
  ATTACH_COLLECTIONS = { 'images' => :images, 'files' => :files }.freeze

  def attach
    @production_order.public_send(attach_collection).attach(params[:files])
    render 'api/v1/accounts/mes/production_orders/show'
  end

  def detach
    @production_order.public_send(attach_collection).find(params[:attachment_id]).purge
    render 'api/v1/accounts/mes/production_orders/show'
  end

  # 业务转发：把订单知会给某阶段负责人（选板块）+ 附言，推站内通知并在订单上留痕。
  def forward
    @production_order.forward_to_board!(
      sender: current_user, board_key: params[:board_key], note: params[:note]
    )
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 退回给业务：工程/PMC 发现业务没把物料细节确认清楚，做不下去，把单退回去让业务补。
  # 能不能退（阶段、是不是本阶段负责人、有没有重复退）全在模型里判，这里只转述原因。
  def return_to_sales
    @production_order.return_to_sales!(actor: current_user, reason: params[:reason])
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # 业务补完细节点「已确认」：解除退回，通知退单的人可以接着做。
  # 权限与 confirm_bom 同口径——这一步是「业务把细节定下来」，只有这张单的归属业务员
  # 本人（或管理员）说了算。原先控制器一道判定都没有：任何能调到这个接口的人都能
  # 替别人把退回点成已确认，退单的工程/PMC 就以为细节谈妥了、照着往下做。
  def resolve_sales_return
    return render json: { error: '只有这张单的归属业务员能确认退回' }, status: :forbidden unless can_resolve_sales_return?

    @production_order.resolve_sales_return!(actor: current_user)
    render 'api/v1/accounts/mes/production_orders/show'
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def audits
    rows = @production_order.audits.order(created_at: :desc).limit(80).map do |audit|
      {
        id: audit.id,
        action: audit.action,
        changed_fields: audit.audited_changes.keys,
        user_name: audit.user&.name || '系统',
        created_at: audit.created_at
      }
    end
    render json: { payload: rows }
  end

  private

  # MES 待办的唯一权威出口。inbox / todo_count / todos / acknowledge 都走它，
  # 不在控制器里另留一套角色推导（判定原件已搬进去，见 Mes::TodoList）。
  def todo_list
    @todo_list ||= Mes::TodoList.new(account: Current.account, account_user: Current.account_user)
  end

  # 推料的折算口径：订单量 / BOM 基准量 = 倍数。
  def issue_plan_meta
    bom = @production_order.bom
    base = bom&.base_qty.to_d
    { order_qty: @production_order.qty, bom_no: bom&.bom_no, bom_base_qty: bom&.base_qty,
      factor: base.zero? ? nil : (@production_order.qty.to_d / base) }
  end

  # 导出范围：默认当月，可传 month=YYYY-MM 或 from/to。只取挂了生产任务单的。
  # 走和列表同一套可见性收口，不另开口子。
  def cost_export_scope
    scope = scoped_by_product_line(Current.account.mes_production_orders)
    scope = scope.where.not(bom_id: nil).includes(bom: :bom_items)
    # 单张导出：任务单和采购单一下出去，财务当天就要这一单的料本对账，
    # 不能等到月底导全月再从几百张里翻。格式与月度那份完全一致（同一个 service）。
    # 按 bom_id 过滤而不是订单 id：一张生产任务单常分批下几张生产订单，各批采购价
    # 可能不同，得把挂在这张任务单上的全部订单一起算，只取一张会漏掉后面几批的价。
    return scope.where(bom_id: params[:bom_id]) if params[:bom_id].present?

    apply_export_period(scope).order(created_at: :desc).limit(500)
  end

  def apply_export_period(scope)
    return scope.where(created_at: Date.strptime(params[:month], '%Y-%m').all_month) if params[:month].present?

    scope = scope.where(created_at: params[:from].to_date.beginning_of_day..) if params[:from].present?
    scope = scope.where(created_at: ..params[:to].to_date.end_of_day) if params[:to].present?
    scope
  end

  def cost_export_filename
    if params[:bom_id].present?
      bom = Current.account.mes_boms.where(id: params[:bom_id]).pick(:doc_no, :bom_no)
      return "生产任务单成本_#{bom&.compact&.find(&:present?) || params[:bom_id]}.xlsx"
    end

    scope = params[:month].presence || Time.zone.today.strftime('%Y-%m')
    "生产任务单成本_#{scope}.xlsx"
  end

  # 跳过采购＝宣布「这批料不用买」，影响后续齐套与成本归集，限 PMC/采购岗与管理员。
  def can_skip_purchasing?
    admin_like? || Current.account_user.mes_can?(:purchase) || Current.account_user.mes_can?(:order)
  end

  # 转单落库字段：成品/数量/单位优先取转单弹窗传来的（明细在那儿逐行确认过），缺则从销售订单带。
  # 转单明细：新版前端传 items 数组（每行一个成品）。
  # 旧版单行参数（crm_product_id/qty/unit）继续认，避免老页面缓存着就转不了单。
  def convert_rows
    permitted = %i[crm_product_id qty unit product_name delivery_date owner_id row]
    raw = params[:items].presence || [params.permit(*permitted)]
    Array(raw).filter_map do |item|
      row = item.respond_to?(:permit) ? item.permit(*permitted) : item
      product_id = row[:crm_product_id].presence&.to_i
      next if product_id.blank? || row[:qty].to_d <= 0

      # row = 明细行号（1 起），转单后按它把产品关联写回销售订单明细。
      { crm_product_id: product_id, qty: row[:qty], unit: row[:unit].presence,
        product_name: row[:product_name].presence, delivery_date: row[:delivery_date].presence,
        owner_id: row[:owner_id].presence, row: row[:row].presence }
    end
  end

  # 同销售订单 + 同成品已有的在办生产订单（已取消的不算，取消后可以重建）。
  # 库存备货单（不挂销售订单）和没选成品的单不判重——它们本来就允许开多张。
  def duplicate_order_for(order)
    return nil if order.crm_sales_order_id.blank? || order.crm_product_id.blank?

    Current.account.mes_production_orders
           .where(crm_sales_order_id: order.crm_sales_order_id, crm_product_id: order.crm_product_id)
           .where.not(status: 'CANCELLED').first
  end

  # 该销售订单下已转过的 产品id → 生产订单号（已取消的不算，取消后可以重转）。
  def converted_product_nos(sales_order)
    Current.account.mes_production_orders
           .where(crm_sales_order_id: sales_order.id).where.not(status: 'CANCELLED')
           .pluck(:crm_product_id, :order_no).to_h
  end

  def save_converted_order(sales_order, row)
    order = build_converted_order(sales_order, row)
    order.fallback_product_line = current_product_line
    order.save!
    order.submit_for_approval!(current_user) unless Current.account_user.mes_can?(:order)
    order
  end

  def build_converted_order(sales_order, row)
    product = Current.account.crm_products.find_by(id: row[:crm_product_id])
    Current.account.mes_production_orders.new(
      converted_order_attrs(sales_order, product, row).merge(
        crm_sales_order: sales_order, crm_product: product, order_kind: 'CUSTOMER',
        # 有 :order 能力者由已确认销售订单转入，直接生效；业务员转入的落草稿等审批（见 convert）。
        approval_status: Current.account_user.mes_can?(:order) ? 'APPROVED' : 'DRAFT'
      )
    )
  end

  def converted_order_attrs(sales_order, product, row)
    {
      crm_customer_id: sales_order.crm_customer_id,
      product_name: row[:product_name] || product&.name,
      qty: row[:qty],
      unit: row[:unit],
      pi_no: sales_order.pi_no,
      delivery_date: row[:delivery_date] || sales_order.delivery_date,
      owner_id: row[:owner_id] || sales_order.owner_id || current_user.id,
      # 转单弹窗里写的备注：一次转多行就每张单都带一份（业务写的多半是整单的交代）。
      remark: params[:remark].presence
    }
  end

  # 每页条数：默认沿用 RESULTS_PER_PAGE(15)，供列表分页；调用方(如报工订单下拉)需一次性
  # 拿到全部在产订单时可传 per_page，封顶 500 防止拉全表。

  # 列表分档：mine=我的客户订单（归属我**或我经办的**）｜ stock=库存备货（全业务共享）｜ all=可见全部。
  #
  # 「我经办的」这一半是 2026-10-30 补的：共享客户里助理建的单，业绩归客户归属人（老板），
  # 生产订单的 owner 跟着也是老板，于是助理在「我的订单」页签里找不到自己做的单，
  # 只能切到「全部」里翻——实测叶爱玲经办的 13 张单有 2 张归陈云钢，就是这么丢的
  # （用户原话：「她只能看到责任人是她自己的单，所以会多次问我们这个单的进度」）。
  # 生产订单表没有经办人这个概念，所以回头去 crm_sales_orders 认 handled_by_id。
  # 这里**只放宽页签筛选**，整体可见范围仍由 ORDER_VISIBLE_SQL 收口，不多给一张单。
  MINE_SQL = <<~SQL.squish.freeze
    mes_production_orders.owner_id = :uid
    OR mes_production_orders.crm_sales_order_id IN (
      SELECT so.id FROM crm_sales_orders so
      WHERE so.account_id = :account_id AND so.handled_by_id = :uid
    )
  SQL

  def apply_list_scope(scope)
    case params[:list_scope]
    when 'mine'
      scope.where(order_kind: 'CUSTOMER')
           .where(MINE_SQL, uid: current_user.id, account_id: Current.account.id)
    when 'stock' then scope.stock
    else scope
    end
  end

  # 关键词搜索：工单号 / 成品名 / 产品料号。
  # 搜工单号 / 成品名 / 商品编码（= 关联产品档案 sku）。
  def apply_column_filters(scope)
    COLUMN_LIKE_FILTERS.each do |param, apply|
      value = params[param]
      scope = apply.call(scope, value.to_s.strip) if value.present?
    end
    scope = scope.where("#{DUE_SQL} >= ?", params[:due_from]) if params[:due_from].present?
    scope = scope.where("#{DUE_SQL} <= ?", params[:due_to]) if params[:due_to].present?
    scope
  end

  def apply_search(scope)
    return scope if params[:q].blank?

    scope.left_joins(:crm_product).where(
      'mes_production_orders.order_no ILIKE :t OR mes_production_orders.product_name ILIKE :t OR crm_products.sku ILIKE :t',
      t: "%#{params[:q].strip}%"
    )
  end

  def fetch_production_order
    @production_order = Current.account.mes_production_orders.find(params[:id])
  end

  def attach_collection
    ATTACH_COLLECTIONS[params[:kind]] || :files
  end

  # 能否处理该阶段：本阶段负责人本人，或管理员/副管理员。
  def can_handle_stage?(order)
    admin_like? || order.current_stage_owner_ids.include?(current_user.id)
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  # 判定收在模型（Mes::ProductionOrder#can_confirm_bom? / #can_resolve_sales_return?），
  # 控制器挡写与 jbuilder 显按钮共用同一处，不各写一份。
  def can_confirm_bom? = @production_order.can_confirm_bom?(Current.account_user)
  def can_resolve_sales_return? = @production_order.can_resolve_sales_return?(Current.account_user)

  # 能否审批当前环节：管理员，或本环节指定审批人本人。
  # 回避：上一级已经是我批的，这一级就不给我点了——一个人连批两级等于这道闸没有。
  # 管理员也挡，否则兼着部门主管的管理员能把自己提的单一路批到生效。
  def can_approve?(order)
    return false unless order.pending_approval?
    return false if acted_previous_level?(order)
    return true if admin_like?

    order.current_approver_id == current_user.id
  end

  # 本单的上一级是否由我经手（指定审批人是我，或我代批的）。
  def acted_previous_level?(order)
    return false unless order.approval_status == 'MANAGER_APPROVED'
    return false if order.manager_acted_at.blank? # 没主管直接转总经理的单不算

    [order.manager_acted_by_id, order.manager_id].compact.include?(current_user.id)
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def inbox_row(order, purchase_state = nil)
    {
      id: order.id,
      order_no: order.order_no,
      product_name: order.product_name,
      stage: order.stage,
      awaiting_ack: order.awaiting_ack?,
      ack_overdue: order.ack_overdue?,
      ack_deadline: order.ack_deadline,
      entered_at: order.stage_entered_at,
      # 采购原料阶段专用：TODO 待下单 / WAITING 等料中 / URGING 逾期催货
      purchase_state: purchase_state,
      purchase_summary: purchase_state && purchase_summary_for(order)
    }
  end

  # 「已下 N 张单 · 最早交期 10/18」/「逾期 N 天」这类右侧小字。
  def purchase_summary_for(order)
    rows = Current.account.mes_purchase_orders
                  .where(production_order_id: order.id).where.not(status: 'CANCELLED')
                  .pluck(:status, :delivery_date, :expected_date)
    return nil if rows.empty?

    dues = rows.reject { |r| r[0] == 'RECEIVED' }.filter_map { |r| r[1] || r[2]&.to_date }
    { count: rows.size, earliest_due: dues.min,
      overdue_days: dues.min && dues.min < Date.current ? (Date.current - dues.min).to_i : nil }
  end

  def check_authorization
    authorize(Mes::ProductionOrder)
  end

  # 编辑权：PMC/管理员不受限；归属业务可改**本人订单（含已下发）**——已下发的改动
  # 由 update 通知下游负责人。无 order 能力且非本人订单则拒。
  def ensure_editable!
    ensure_owner_or_admin!(@production_order, '生产订单')
  end

  # 无 :order 能力的业务角色（业务员/业务主管）建单、改单的收口：
  #   · 单子只能挂自己名下，不能代建；备货单的 owner 是「责任人」，同样锁本人；
  #   · 业务订单必须关联 CRM 销售订单（带出 PI 号）；
  #   · 备货单放行（2026-10-06 改）——对业务员而言这张单就是「备货申请」：
  #     照常落草稿走三级审批，PMC/主管/总经理点头才进生产，故不另做申请单据。
  # 返回 false = 已渲染错误，调用方直接 return。
  def apply_sales_user_limits!(order)
    return true if Current.account_user.mes_can?(:order)

    order.owner_id = current_user.id
    order.order_kind = 'CUSTOMER' unless order.stock?
    return true if order.stock? || order.crm_sales_order_id.present?

    render json: { error: '请先关联 CRM 销售订单（订单编号从销售订单下拉选择）' }, status: :unprocessable_entity
    false
  end

  # 删除权：管理员删任意；其余仅能删**本人的草稿**（已下发进入生产流程不可删）。
  def ensure_deletable!
    return if admin_like?
    return unless @production_order.owner_id == current_user.id
    # 草稿，或者虽已生效但什么都还没开始（见 deletable_by_owner? 的注释）。
    return if @production_order.is_draft || @production_order.deletable_by_owner?

    render json: { error: '这张单已经往下走了（已领料/采购/入库），不能删。请联系管理员作废。' },
           status: :forbidden
  end

  def production_order_params
    permitted = params.require(:production_order).permit(
      # 单号允许手工填（两账并行期要对上金蝶的号）。**只在新建时放行**——
      # 改已生效单据的号会让纸质单、下游单据和 ERP 全部对不上。留空则自动生成。
      *(action_name == 'create' ? [:order_no] : []),
      :crm_sales_order_id, :crm_customer_id, :crm_product_id, :product_name, :qty, :unit, :pi_no,
      :bom_id, :order_kind, :intake_kind, :delivery_date, :planned_start_date, :planned_end_date,
      :actual_start_date, :actual_end_date, :owner_id, :remark, :product_line,
      images: [], files: [] # 建单时挂载已暂存的 blob signed_id
    )
    # stage/status/produced_qty 由状态机（接单/领料/报工/出库过账）驱动，销售端不得直接改单越过流程；
    # 仅持生产订单管理能力(:order)者可手工干预。
    if Current.account_user&.mes_can?(:order)
      permitted.merge!(params.require(:production_order).permit(:stage, :status, :produced_qty).to_h)
    end
    # spec 为按产品线的定制规格 jsonb（字段动态），整体透传。
    raw_spec = params.require(:production_order)[:spec]
    permitted[:spec] = raw_spec.respond_to?(:permit!) ? raw_spec.permit!.to_h : raw_spec if raw_spec.present?
    permitted
  end
end
