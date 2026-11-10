# == Schema Information
#
# Table name: mes_stock_entries
#
#  id                        :bigint           not null, primary key
#  actual_inbound_date       :datetime
#  approval_status           :string           default("APPROVED"), not null
#  approved_at               :datetime
#  color                     :string
#  entry_no                  :string           not null
#  extra_purchase_order_ids  :bigint           default([]), not null, is an Array
#  is_checked                :boolean          default(FALSE), not null
#  posted_at                 :datetime
#  print_count               :integer          default(0), not null
#  product_line              :string
#  purpose                   :string           not null
#  reject_reason             :text
#  remark                    :text
#  status                    :string           default("DRAFT"), not null
#  warehouse_confirmed_at    :datetime
#  workshop_confirmed_at     :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  approved_by_id            :bigint
#  checked_by_id             :bigint
#  from_warehouse_id         :bigint
#  outsource_order_id        :bigint
#  owner_id                  :bigint
#  production_order_id       :bigint
#  purchase_order_id         :bigint
#  received_by_id            :bigint
#  to_warehouse_id           :bigint
#  warehouse_confirmed_by_id :bigint
#  workshop_confirmed_by_id  :bigint
#
# Indexes
#
#  index_mes_stock_entries_on_account_and_approval       (account_id,approval_status)
#  index_mes_stock_entries_on_account_and_product_line   (account_id,product_line)
#  index_mes_stock_entries_on_account_id                 (account_id)
#  index_mes_stock_entries_on_account_id_and_entry_no    (account_id,entry_no) UNIQUE
#  index_mes_stock_entries_on_account_id_and_purpose     (account_id,purpose)
#  index_mes_stock_entries_on_extra_purchase_order_ids   (extra_purchase_order_ids) USING gin
#  index_mes_stock_entries_on_outsource_order_id         (outsource_order_id)
#  index_mes_stock_entries_on_owner_id                   (owner_id)
#  index_mes_stock_entries_on_production_order_id        (production_order_id)
#  index_mes_stock_entries_on_purchase_order_id          (purchase_order_id)
#  index_mes_stock_entries_on_warehouse_confirmed_by_id  (warehouse_confirmed_by_id)
#  index_mes_stock_entries_on_workshop_confirmed_by_id   (workshop_confirmed_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (production_order_id => mes_production_orders.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => nullify
#  fk_rails_...  (warehouse_confirmed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (workshop_confirmed_by_id => users.id) ON DELETE => nullify
#
class Mes::StockEntry < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  include Mes::Returnable

  # 一表多用（ERPNext Stock Entry 模式）。SHIPMENT=成品出库（销售出库开单时内部生成）。
  #
  # OPENING=期初库存：上线前仓库里实际存在、却没走过系统采购的货。
  # 不走 MATERIAL_RECEIPT 是因为那条路过账会出「借存货/贷应付账款」的凭证，
  # 给谁都不是的供应商凭空挂一笔应付。期初只加结存、记流水，不出凭证、不绑生产订单、
  # 不推阶段（故 FLOW_MIN_STAGE / STAGE_ADVANCE / PAYABLE_VOUCHER_PURPOSES 都不收录它），
  # 成本层也不建——成品的 FIFO 期初要带单价，走 Erp::StockOpeningImportService 单独导。
  # PURCHASE_RETURN 采购退货：供应商送错货/送来不合格的，退回去。
  # 出库方向（货离开仓库），过账时把采购单的到货量冲回去——不冲的话采购单还显示「已到料」，
  # 齐套徽标和到货明细都会以为这批料在库，没人知道要催供应商重发。
  # 退了不打算再要的，去采购单上按「关闭」结掉（已有动作，回冲在途并退出齐套判定）。
  #
  # ⚠️ 不要复用 MATERIAL_RETURN：那个是**生产退料回库**（入库方向，成本侧 return_materials!
  # 建层、备注写「生产退料」）。只有 ERP 应付侧把它误当成采购退货——见下面 PAYABLE_VOUCHER_PURPOSES。
  #
  # 委外三张单（OUTSOURCE_*，见 Mes::OutsourceOrder）与上面那些不同的地方是**两个仓都动**：
  # 料发给加工厂不是消失了，是从原料仓挪到了委外仓——料还是我们的。所以它们走
  # TRANSFER_PURPOSES 这条支线，一行刷两个仓的结存、记两条流水。
  PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_ISSUE MATERIAL_RETURN PURCHASE_RETURN MANUFACTURE SCRAP SHIPMENT OPENING
                CONVERT_TO_PRODUCT CONVERT_TO_MATERIAL
                OUTSOURCE_ISSUE OUTSOURCE_RECEIPT OUTSOURCE_RETURN].freeze
  IN_PURPOSES = %w[MATERIAL_RECEIPT MATERIAL_RETURN MANUFACTURE OPENING OUTSOURCE_RECEIPT].freeze

  # 仓到仓：from_warehouse_id 扣、to_warehouse_id 加，同一行刷两个仓。
  # 委外发料＝原料仓→委外仓；委外退料＝委外仓→原料仓/不良品仓。
  TRANSFER_PURPOSES = %w[OUTSOURCE_ISSUE OUTSOURCE_RETURN].freeze

  # 委外产品入库一单两类行（同转换单的做法）：产出品行进成品仓(+)，
  # 倒冲料行从委外仓扣(-)——加工厂把料做成了货，委外仓里那批料就该同步消掉，
  # 不扣的话委外仓会一直虚增，和生产上现在「期初之后再没动过」是同一个毛病。
  BACKFLUSH_PURPOSE = 'OUTSOURCE_RECEIPT'.freeze

  # ── 原料↔成品转换 ─────────────────────────────────────────────
  # 同一个编码在 MES 里有两本数量账（item_type=MATERIAL / PRODUCT）：采购入库永远落原料账，
  # 销售出库永远从成品账扣。整机外购转卖、或同一个屏既当零件又整台卖的货，买进来在原料账、
  # 要卖却得从成品账扣，中间缺一个换身份的动作——以前只能手开两张互不相干的单，台账上看着
  # 像「原料莫名少了、成品莫名多了」。
  #
  # 转换单一单两行：同一个商品、同一个仓库，一行 MATERIAL 一行 PRODUCT，数量相等，
  # 方向由 purpose 定（转成品=成品进原料出，转原料=反过来）。
  #
  # ⚠️ 成本层(erp_stock_layers)一根手指都不碰：层按 (商品, 仓库) 记、**没有 item_type**，
  # 两本数量账共用同一批层。转换时再建层/扣层就是把同一批货的成本算两遍。
  CONVERT_PURPOSES = %w[CONVERT_TO_PRODUCT CONVERT_TO_MATERIAL].freeze
  STATUSES = %w[DRAFT POSTED CANCELLED].freeze

  # 过账前的财务审核闸。2026-10-21 财务与仓库约定**原料入库不再逐单审批**：仓管自行
  # 过账，月底把送货单整叠转给财务核对——一张单等一次审核，生产上 40 张入库单就这么
  # 卡在「待审核」上。清空这个清单即整条闸失效（needs_approval? 恒 false，过账按钮不再
  # 禁用、审核/驳回按钮不再出现），审核机制本身留着：流程要收回去，把 purpose 填回来即可。
  APPROVAL_STATUSES = %w[PENDING APPROVED REJECTED].freeze
  APPROVAL_REQUIRED_PURPOSES = [].freeze
  # 审核人按产品线配置，复用 Mes::BoardOwner（同采购审批人那套，见 Mes::PurchaseOrder）。
  APPROVER_BOARD_KEY = 'mes_stock_approver'.freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', optional: true
  # 委外的发料/产品入库/退料三张单都挂回加工单（见 Mes::OutsourceOrder）。
  belongs_to :outsource_order, class_name: 'Mes::OutsourceOrder', optional: true

  # 本单关联的全部采购单 id（主单 + 追加的）。同一家供应商同一天送来好几张单的料，
  # 仓管一次收完比开三张入库单省事（照采购单挂多张生产订单那套，见 Mes::PurchaseOrder）。
  def all_purchase_order_ids
    ([purchase_order_id] + extra_purchase_order_ids.to_a).compact.uniq
  end

  def related_purchase_orders
    account.mes_purchase_orders.where(id: all_purchase_order_ids).order(:id)
  end
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :checked_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  belongs_to :received_by, class_name: 'User', optional: true
  belongs_to :workshop_confirmed_by, class_name: 'User', optional: true
  belongs_to :warehouse_confirmed_by, class_name: 'User', optional: true
  has_many :stock_entry_items, class_name: 'Mes::StockEntryItem', dependent: :destroy, inverse_of: :stock_entry
  accepts_nested_attributes_for :stock_entry_items, allow_destroy: true

  # 收货单留证（原料入库必传，校验在控制器）。
  has_many_attached :receipts

  validates :entry_no, presence: true, uniqueness: { scope: :account_id }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :status, inclusion: { in: STATUSES }
  validate :enforce_flow_prerequisite, on: :create
  validate :enforce_convert_pairing
  # 建单当场拦重复/超量成品入库：当面说清「已入 X/Y」，而不是放它存下去、几天后在仓管那儿爆。
  validate :enforce_fg_inbound_quota, on: :create

  # ── 流程硬锁 ──：下游库存单必须等生产订单走到对应阶段才能开单，前面工序没做完后端直接拒绝。
  #   原料入库→须已采购；生产领料→须原料已入库；成品入库→须已领料+进入生产(报工)。
  #   外购订单只走 采购→收货入成品仓→出库，禁止生产领料/成品入库。
  # 开这张单之前，生产订单最少要走到哪一步。
  #
  # ⚠️ 领料（MATERIAL_ISSUE）2026-11-10 从「原料入库」降到「采购原料」：
  # 阶段推进常常滞后于实物——料早到仓库了，单子还挂在「采购原料」。卡在原来那条线上，
  # 42 张在产订单里 27 张开不了领料单，而车间手里的料是实实在在的。
  # 真正的保护是 stock_shortages（按仓实际结存逐行校验），不是这道流程闸：
  # 库存不够照样过不了账，所以降这一档不会放出负库存。
  # 再往前（待工程接单 / 生产任务单）不降——那时候连 BOM 都没有，不知道该领什么料。
  FLOW_MIN_STAGE = {
    'MATERIAL_RECEIPT' => 'PURCHASING',
    'MATERIAL_ISSUE' => 'PURCHASING',
    'MANUFACTURE' => 'PRODUCTION'
  }.freeze
  FLOW_PREREQ_LABEL = {
    'MATERIAL_RECEIPT' => '采购下单',
    'MATERIAL_ISSUE' => '采购下单',
    'MANUFACTURE' => '生产领料、生产报工'
  }.freeze
  OUTSOURCE_FORBIDDEN_PURPOSES = %w[MATERIAL_ISSUE MANUFACTURE].freeze

  before_create :stamp_workshop_confirm
  before_create :stamp_pending_approval
  before_update :reopen_approval_on_edit
  after_create :notify_warehouse_count_pending
  after_create :notify_material_return_pending

  scope :posted, -> { where(status: 'POSTED') }

  def self.document_number_prefix = 'SE'
  def self.document_number_column = :entry_no

  # ── 单据退回（Mes::Returnable）──：库存单一表多用，本板块与上游按 purpose 而定。
  #   原料入库(MATERIAL_RECEIPT) → 上游=采购；生产领料(MATERIAL_ISSUE) → 上游=原料入库；
  #   成品入库(MANUFACTURE) → 上游=生产报工。
  RETURN_BOARD_BY_PURPOSE = {
    'MATERIAL_RECEIPT' => 'mes_stock_entries_index',
    'MATERIAL_ISSUE' => 'mes_material_issues_index',
    'MANUFACTURE' => 'mes_fg_inbound_index'
  }.freeze
  RETURN_LABEL_BY_PURPOSE = {
    'MATERIAL_RECEIPT' => '原料入库单',
    'MATERIAL_ISSUE' => '生产领料单',
    'MANUFACTURE' => '成品入库单',
    'PURCHASE_RETURN' => '采购退货单',
    'MATERIAL_RETURN' => '生产退料单'
  }.freeze

  # 单据归谁管（判谁能开/改/过账）。与上面的退回链路分开写：
  # 生产退料跟生产领料是同一拨人（车间开单、仓管收料），但它不参与「退回上游」那套流程——
  # 料都退回仓库了，再把单据退回上游没有意义。
  BOARD_BY_PURPOSE = RETURN_BOARD_BY_PURPOSE.merge(
    'MATERIAL_RETURN' => 'mes_material_issues_index'
  ).freeze

  def document_board_key = BOARD_BY_PURPOSE[purpose] || 'mes_stock_entries_index'

  # 这个人能不能开 / 改 / 过账这张单。
  #
  # 仓管（stock）全线通吃；成品入库由车间（report）自己开；除此之外，
  # 「这条产线这个板块的负责人」也能操作本板块的单（Mes::BoardOwner，按产线×板块配，
  # 在「设置阶段负责人」里改）。平板车间的生产领料配的就是杨义（MES 角色「生产」）。
  #
  # 放在模型上是因为**列表也要逐条判**：前端按 mes_can?('stock') 藏按钮的话，
  # 杨义建得出单却看不到「过账 / 删单 / 退回」，单子永远停在草稿、报工那边一直显示
  # 「没有可报工的生产订单」（2026-10-16 生产反馈，10-27 实锤）。
  def operable_by?(account_user)
    return false if account_user.blank?
    return true if account_user.mes_can?(:stock)
    return true if purpose == 'MANUFACTURE' && account_user.mes_can?(:report)

    Mes::BoardOwner.manager?(account_user.account, document_board_key,
                             effective_product_line, account_user.user_id)
  end

  # 建单时 product_line 还没 stamp（那是 before_validation 干的），
  # 按 Mes::LineScoped 同样的优先级现算：显式 > 父级带出。
  def effective_product_line
    product_line.presence || product_line_source&.product_line.presence
  end

  def return_document_label = RETURN_LABEL_BY_PURPOSE[purpose] || '库存单'
  def return_document_no = entry_no
  # 只有未过账(DRAFT)的库存单可退回；已过账写了不可改的库存流水，要撤须走冲销。
  def returnable? = status == 'DRAFT' && RETURN_BOARD_BY_PURPOSE.key?(purpose)

  # ── 成品入库交接闸 ──：车间（report）开单=交接发起、自动盖车间章；
  # 仓库（stock）清点数量确认=盖仓库章并直接过账入库。
  def dual_confirm_required? = purpose == 'MANUFACTURE'
  def dual_confirmed? = workshop_confirmed_at.present? && warehouse_confirmed_at.present?

  # 仓库清点确认：盖仓库章后直接过账（确认即入库生效）。
  # 这张单要不要走审核。成品入库/领料/报废那些不走。
  def needs_approval? = APPROVAL_REQUIRED_PURPOSES.include?(purpose)

  def approved? = !needs_approval? || approval_status == 'APPROVED'

  # 过账前的审核闸。拦住就把原因原话抛给前端，别让仓管对着一个灰按钮猜。
  # 缺料明细（只读）。过账预检和 AI 诊断共用——两边各查一遍迟早对不上。
  def stock_shortages
    outgoing_items.filter_map do |item|
      wh = item.warehouse_id || default_warehouse_id
      on_hand = account.mes_stock_balances.find_by(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, warehouse_id: wh
      )&.qty.to_d
      next if on_hand >= item.effective_qty.to_d

      { item: item, item_name: item_display_name(item), item_type: item.item_type,
        crm_product_id: item.crm_product_id, warehouse_id: wh,
        on_hand: on_hand, need: item.effective_qty.to_d }
    end
  end

  def approval_blocker
    return nil if approved?
    return '这张入库单被驳回了，改完会自动回到待审核，等财务重新审核' if approval_status == 'REJECTED'

    '这张入库单还没经财务审核，审核通过才能过账'
  end

  def approve!(actor)
    with_lock do
      raise StandardError, '这张单不需要审核' unless needs_approval?
      raise StandardError, '已经审核通过了' if approval_status == 'APPROVED'

      update!(approval_status: 'APPROVED', approved_by: actor, approved_at: Time.current, reject_reason: nil)
    end
    self
  end

  def reject!(actor, reason)
    raise StandardError, '驳回要填原因' if reason.to_s.strip.blank?

    with_lock do
      raise StandardError, '这张单不需要审核' unless needs_approval?
      raise StandardError, '已过账的单不能驳回，请用「作废」冲销' if status == 'POSTED'

      update!(approval_status: 'REJECTED', approved_by: actor, approved_at: Time.current,
              reject_reason: reason.to_s.strip)
    end
    self
  end

  # 谁能审：配了审核人就只认配置的那些人；没配就回落到财务（用户原话「入库单由财务审核」），
  # 管理员/副管理员一直都能兜底。这样不配也能用，配了就收紧。
  def self.approver?(account, account_user)
    return false if account_user.blank?

    configured = account.mes_board_owners.where(board_key: APPROVER_BOARD_KEY)
                        .pluck(:manager_ids).flatten.compact.uniq
    return configured.include?(account_user.user_id) if configured.any?

    account_user.administrator? || account_user.crm_deputy_admin? || account_user.crm_finance?
  end

  def confirm_warehouse!(actor)
    raise StandardError, '仅成品入库单需要仓库清点确认' unless dual_confirm_required?
    raise StandardError, '单据已过账或已作废，无法确认' unless status == 'DRAFT'
    raise StandardError, '仓库已清点确认，无需重复' if warehouse_confirmed_at.present?

    update!(warehouse_confirmed_at: Time.current, warehouse_confirmed_by_id: actor&.id)
    post!
    self
  end

  # 过账：按 purpose 方向对每个明细刷结存、记流水，然后置 POSTED。
  # 原料入库过账把关联生产订单推进到「原料入库」阶段。
  def post!
    # with_lock 加行锁并开事务：持锁后重新校验状态，杜绝并发/双击重复过账（结存、收货量翻倍）。
    with_lock do
      raise StandardError, '单据已过账或已作废' unless status == 'DRAFT'
      raise StandardError, approval_blocker if approval_blocker
      raise StandardError, '成品入库需车间负责人与仓管共同确认后方可过账' if dual_confirm_required? && !dual_confirmed?

      ensure_purchase_orders_approved!

      lock_parent_for_over_receipt!
      ensure_no_fg_over_inbound!
      # 出库方向(领料/报废/出库)过账前校验结存充足，杜绝超领→负库存。
      ensure_stock_available_for_out!

      ts = Time.current
      stock_entry_items.each { |item| post_item(item, ts) }
      update_columns(status: 'POSTED', posted_at: ts, updated_at: ts)
      apply_purchase_receipt(posting: true)
      advance_production_order_on_receipt(ts)
      complete_production_order_if_fg_full(ts)
      complete_production_order_if_shipped(ts)
      sync_erp_stock_cost
    end
    settle_after_post
    # 应付台账不在这里起账了（2026-10-21）：财务定的流程是**先跟供应商对账、对好了再建账**，
    # 收货即建账会把还没核对的数字先摆进欠款里。这一笔现在进应付管理的「待对账」清单
    # （Erp::LedgerBuilderService#pending_reconciliation 按已过账收货实时算），
    # 财务确认后才落台账。凭证照出——那是总账口径，与业务账的对账流程互不等待。
    self
  end

  # 采购入库与采购退货生成待过账的应付凭证（口径见 ERP_SPEC §8.2bis）。
  # 其它用途（领料/成品入库/报废/销售出库）不在此列：
  # 领料与成品入库是存货内部结转、销售出库的凭证由出库单自己出。
  #
  # 2026-10-26 把 MATERIAL_RETURN 换成 PURCHASE_RETURN：MATERIAL_RETURN 在 MES 和成本侧
  # 都是**生产退料回库**（车间把没用完的料退回仓库），跟供应商没有半点关系，却会凭空
  # 生成一张红字应付凭证冲供应商的账。生产上至今一张退料单都没开过，所以没发作——
  # 谁开第一张就中。
  PAYABLE_VOUCHER_PURPOSES = %w[MATERIAL_RECEIPT PURCHASE_RETURN].freeze

  def generate_erp_receipt_voucher
    return unless PAYABLE_VOUCHER_PURPOSES.include?(purpose)

    Erp::AutoVoucherService.new(account).for_stock_receipt(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::AutoVoucher] 出入库单 #{entry_no} 生成凭证失败: #{e.message}")
  end

  # 作废（冲销）：把过账时扣/加的库存按反方向冲回、记反向流水，已过账才可作废；
  # 若关联生产订单仍停在本单推进到的阶段且无其它已过账领料单，则回退一阶段。保留单据（置 CANCELLED）可追溯。
  def cancel!
    with_lock do
      raise StandardError, '单据尚未过账，草稿可直接删除、无需作废' unless status == 'POSTED'

      ts = Time.current
      # 仓到仓的作废要把两个仓都冲回去（见 post_transfer_item），不能只冲一头。
      stock_entry_items.each do |item|
        transfer? ? post_transfer_item(item, ts, -1) : move_stock!(item, ts, -line_sign(item))
      end
      apply_purchase_receipt(posting: false)
      revert_production_order_stage_on_void(ts)
      # 存货层回滚：入库撤层、出库还层。这里**不吞异常**——「已出库的入库单不许作废」是
      # 成本正确性的硬闸，吞掉就会让层被撤掉、后续出库拿错成本。
      Erp::StockCostService.new(account).reverse_entry!(self)
      update_columns(status: 'CANCELLED', updated_at: ts)
    end
    self
  end

  private

  # 成品存货 FIFO：入库建批次层、出库按先进先出逐层扣（金额只落 erp_* 表，MES 不持有金额）。
  # ERP 是下游，不能反过来挡住仓库过账，所以过账路径上的异常只记日志——
  # 层缺了财务在存货页看得见，可手工补层；作废路径则不吞（见 cancel!）。
  def sync_erp_stock_cost
    Erp::StockCostService.new(account).sync_entry!(self)
  rescue StandardError => e
    Rails.logger.error("[Erp::StockCost] 库存单 #{entry_no} 成本核算失败: #{e.message}")
  end

  # 转换单的两行必须真正配成一对：同商品、同仓库、一进一出、数量相等。
  # 不配对就不是「换身份」而是凭空增减库存——两本账会从此对不上，且没人知道该信哪本。
  def enforce_convert_pairing
    return unless CONVERT_PURPOSES.include?(purpose)

    rows = stock_entry_items.reject(&:marked_for_destruction?)
    blocker = convert_rows_blocker(rows)
    return errors.add(:base, blocker) if blocker

    rows.group_by { |i| [i.crm_product_id, i.warehouse_id] }.each_value { |pair| validate_convert_pair(pair) }
  end

  def convert_rows_blocker(rows)
    return '转换单至少要有一个商品' if rows.empty?
    return '转换单只认商品档（不支持物料档条目）' if rows.any? { |i| i.crm_product_id.blank? }

    nil
  end

  def validate_convert_pair(pair)
    by_type = pair.group_by(&:item_type)
    name = item_display_name(pair.first)
    return errors.add(:base, "#{name}：转换单每个商品要一行原料、一行成品") unless
      by_type.keys.sort == %w[MATERIAL PRODUCT] && pair.size == 2

    out_qty = by_type['MATERIAL'].first.effective_qty
    in_qty = by_type['PRODUCT'].first.effective_qty
    return errors.add(:base, "#{name}：转换数量要大于 0") unless out_qty.positive?

    errors.add(:base, "#{name}：转换前后数量必须一致（原料 #{fnum(out_qty)}、成品 #{fnum(in_qty)}）") if out_qty != in_qty
  end

  # 流程硬锁校验：越级开下游单直接拦下（前端也会隐藏不可选订单，此处为后端兜底）。
  def enforce_flow_prerequisite
    return unless FLOW_MIN_STAGE.key?(purpose)

    po = production_order
    return if po.nil? # 无生产订单的临时库存单（如外购成品备货收货、盘盈）不受脊柱闸约束

    doc = RETURN_LABEL_BY_PURPOSE[purpose] || '库存单'
    if po.outsourced? && OUTSOURCE_FORBIDDEN_PURPOSES.include?(purpose)
      return errors.add(:base, "外购订单不做#{doc}：外购成品经「采购 → 收货」直接入成品仓")
    end
    return if po.stage_reached?(FLOW_MIN_STAGE[purpose])

    stage_cn = Mes::ProductionOrder::STAGE_LABELS[po.stage] || po.stage
    errors.add(:base, "生产订单当前在「#{stage_cn}」阶段，需先完成#{FLOW_PREREQ_LABEL[purpose]}才能开#{doc}")
  end

  # 成品入库防重复/防超量：同一生产订单已过账入库累计 + 本单成品量不得超过订单数量。
  # 收齐后再开 → 「已收齐不能重复入库」；未收齐但本次超出剩余 → 「不能超量入库」。
  # 仅约束成品入库(MANUFACTURE)且挂了生产订单的单据；其余库存单不受影响。
  def enforce_fg_inbound_quota
    msg = fg_over_inbound_error
    errors.add(:base, msg) if msg
  end

  # 防超量在并发下失效——把「读累计→校验→写入」关进同一个临界区。
  # 成品入库锁生产订单，委外产品入库锁委外加工单；不锁的话两个人同时过账，
  # 各自读到的「已收」都是旧的，两张单都判定没超。
  def lock_parent_for_over_receipt!
    production_order&.lock! if purpose == 'MANUFACTURE'
    outsource_order&.lock! if purpose == BACKFLUSH_PURPOSE
  end

  def ensure_no_fg_over_inbound!
    msg = fg_over_inbound_error
    raise StandardError, msg if msg

    msg = outsource_over_receipt_error
    raise StandardError, msg if msg
  end

  # 委外产品入库超收（与上面成品入库那条同一个毛病，口径也照它）：
  # build_receipt 只在**建单那一刻**比过「还差多少」，所以连开两张满额草稿都建得出来，
  # 过账时各自看各自的，两张都能过——实测 120 的单收成了 240。
  # 把闸放在过账这一步，按「本单之外已过账的量」重算。
  def outsource_over_receipt_error
    order = outsource_order_for_receipt_check
    return nil if order.nil?

    others = other_posted_receipt_qty
    mine = stock_entry_items.select { |i| i.item_type == 'PRODUCT' }.sum { |i| i.qty.to_d }
    return nil if others + mine <= order.qty.to_d

    "委外加工单 #{order.order_no} 应收 #{fnum(order.qty)}，已收 #{fnum(others)}，" \
      "本单再收 #{fnum(mine)} 就超了"
  end

  # 只有「委外产品入库 + 挂了加工单 + 加工单有应收数量」才需要查超收。
  def outsource_order_for_receipt_check
    return nil if purpose != BACKFLUSH_PURPOSE || outsource_order_id.blank?

    order = outsource_order
    order.nil? || order.qty.to_d <= 0 ? nil : order
  end

  # 本单之外、这张加工单上已过账的产出数量。
  def other_posted_receipt_qty
    account.mes_stock_entries.posted
           .where(outsource_order_id: outsource_order_id, purpose: BACKFLUSH_PURPOSE)
           .where.not(id: id)
           .joins(:stock_entry_items)
           .where(mes_stock_entry_items: { item_type: 'PRODUCT' })
           .sum('mes_stock_entry_items.qty')
  end

  # 超量原因（无问题返回 nil）。建单校验与过账闸共用——
  # 只在过账拦是不够的：建单在车间、过账在仓库，中间隔着好几天，
  # 车间把单建出来就以为交接完了，错误却出现在几天后仓管的屏幕上，
  # 两头都不知道发生了什么（生产上因此积了 6 张永远过不了账的重复单）。
  def fg_over_inbound_error
    return nil unless purpose == 'MANUFACTURE'

    po = production_order
    return nil if po.nil? || po.qty.to_d <= 0

    already = po.fg_inbound_qty # 已过账累计（不含本张草稿）
    remaining = po.qty.to_d - already
    # 用 effective_qty(实收优先)与真实刷库口径一致，防「实收>计划」时按 qty 判定通过却超量入库。
    incoming = stock_entry_items.select { |i| i.item_type == 'PRODUCT' }.sum { |i| i.effective_qty.to_d }

    if remaining <= 0
      "该订单成品已入库收齐（#{fnum(already)}/#{fnum(po.qty)}），不能重复入库"
    elsif incoming > remaining
      "入库数量超出订单剩余（订单 #{fnum(po.qty)}，已入 #{fnum(already)}，剩 #{fnum(remaining)}，本次 #{fnum(incoming)}），不能超量入库"
    end
  end

  def fnum(value)
    format('%g', value.to_f)
  end

  def product_line_source = production_order || purchase_order

  # 车间开单即视为车间确认（开单人盖章）。
  # 被驳回的单改完自动回到「待审核」，不用仓管再找一个「重新提交」按钮
  # （驳回原因留着，财务能看出上一轮是为什么退的）。
  # 审核动作自己改 approval_status，不能被这里又翻回去。
  def reopen_approval_on_edit
    return unless approval_status == 'REJECTED' && !approval_status_changed?
    return if (changes.keys - %w[updated_at]).empty?

    self.approval_status = 'PENDING'
  end

  # 建单即「待审核」。原料入库没有草稿/提交两步——单子开出来就是等财务看的那张，
  # 再多一次「提交」点击只会多一步没人记得做的操作。
  def stamp_pending_approval
    self.approval_status = needs_approval? ? 'PENDING' : 'APPROVED'
  end

  def stamp_workshop_confirm
    return unless dual_confirm_required?

    self.workshop_confirmed_at ||= Time.current
    self.workshop_confirmed_by_id ||= owner_id
  end

  # 车间开成品入库单后通知仓库（成品入库板块负责人）清点确认。
  def notify_warehouse_count_pending
    return unless dual_confirm_required?

    recipients = Mes::BoardOwner.notify_ids(account, 'mes_fg_inbound_index', product_line)
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'fg_count_pending',
      title: "成品入库待仓库清点：#{entry_no}",
      body: "#{owner&.name || '车间'}已开成品入库单#{production_order ? "（#{production_order.order_no}）" : ''}，请仓库清点数量确认入库。",
      order: production_order
    )
  end

  # 过账之后、事务之外要办的两件事：办结待办 + 出凭证。
  # 都不属于库存原子性，塞进 with_lock 只会把 post! 撑长。
  def settle_after_post
    # 收完料就把那条「待收料」办结，不然过完账还挂在仓管待办里。
    Mes::Notifier.resolve(account: account, kinds: 'material_return_pending', title_like: entry_no)
    # 采购入库/退货出应付凭证（借 存货科目 / 贷 应付账款，退货红字）。
    generate_erp_receipt_voucher
  end

  # 车间开生产退料单后通知**原料仓管**去收料、过账。
  #
  # 不发的话这条流程是断的：车间开完是草稿，而过账按钮只给仓管（mesCan('stock')），
  # 仓管又没有任何提示——料堆在车间，单子一直躺着没人动。
  #
  # 收件人取**原料入库板块**（mes_stock_entries_index）的负责人，不是领料板块：
  # 退的是原料、回的是原料仓，收货的就是那拨人；而领料板块在平板线上配的是
  # 杨义（生产岗），通知那块等于通知开单的人自己。
  def notify_material_return_pending
    return unless purpose == 'MATERIAL_RETURN'

    recipients = Mes::BoardOwner.notify_ids(account, 'mes_stock_entries_index', product_line) - [owner_id]
    Mes::Notifier.notify(
      account: account, recipients: recipients, kind: 'material_return_pending',
      title: "待收料：生产退料 #{entry_no}",
      body: "#{owner&.name || '车间'}退回 #{stock_entry_items.size} 项物料" \
            "#{production_order ? "（#{production_order.order_no}）" : ''}，请清点后过账。",
      order: production_order
    )
  end

  def post_item(item, timestamp)
    return post_transfer_item(item, timestamp, 1) if transfer?

    sign = line_sign(item)
    balance_after = move_stock!(item, timestamp, sign)
    # 出库兜底：持锁扣减后结存为负=超领/超发，抛错回滚整单(领料/报废/出库),杜绝负库存。
    return unless sign == -1 && balance_after.negative?

    raise StandardError, "#{item_display_name(item)} 库存不足（扣减后结存 #{fnum(balance_after)}），无法过账"
  end

  # 仓到仓一行刷两个仓：发出仓扣、接收仓加。dir=1 过账，dir=-1 作废冲销。
  # 扣的那一头要查负库存（料不够就发不出去），加的那一头不用。
  def post_transfer_item(item, timestamp, dir)
    out_wh = item.warehouse_id || from_warehouse_id
    in_wh = to_warehouse_id
    raise StandardError, "#{item_display_name(item)} 缺发出仓或接收仓" if out_wh.nil? || in_wh.nil?

    balance_after = move_stock!(item, timestamp, -dir, warehouse_id: out_wh)
    move_stock!(item, timestamp, dir, warehouse_id: in_wh)
    return unless dir == 1 && balance_after.negative?

    raise StandardError, "#{item_display_name(item)} 库存不足（扣减后结存 #{fnum(balance_after)}），无法过账"
  end

  # 单条明细刷结存 + 记流水，返回扣减后结存。sign=direction_sign 为过账，-direction_sign 为作废冲销。
  def move_stock!(item, timestamp, sign, warehouse_id: nil)
    warehouse_id ||= item.warehouse_id || default_warehouse_id
    raise StandardError, "明细缺仓库（#{item.item_type}）" if warehouse_id.nil?

    delta = sign * item.effective_qty
    balance_after = Mes::StockBalance.apply!(
      account_id: account_id, item_type: item.item_type, warehouse_id: warehouse_id,
      mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id, delta: delta
    )
    account.mes_stock_ledgers.create!(
      item_type: item.item_type, mes_material_id: item.mes_material_id, crm_product_id: item.crm_product_id,
      warehouse_id: warehouse_id, stock_entry_id: id, qty_change: delta, balance_after: balance_after, posted_at: timestamp
    )
    balance_after
  end

  def item_display_name(item)
    item.mes_material&.name || item.crm_product&.name || "物料##{item.mes_material_id || item.crm_product_id}"
  end

  # 出库(领料/报废/出库)过账前预检结存充足，一次性列出所有缺料，避免超领把库存刷成负数。
  def ensure_stock_available_for_out!
    rows = stock_shortages
    return if rows.empty?

    text = rows.map { |r| "#{r[:item_name]}（结存 #{fnum(r[:on_hand])}，需 #{fnum(r[:need])}）" }
    raise StandardError, "库存不足，无法出库：#{text.join('；')}"
  end

  # 要扣库存的那些行。整单同向的 purpose 要么全是、要么一行没有；转换单一单两行各占一个方向。
  def outgoing_items
    stock_entry_items.select { |item| line_sign(item) == -1 }
  end

  # 作废回退阶段：仅当生产订单仍停在本单过账时推进到的阶段（to_stage）、
  # 且该订单已无其它已过账同类单据时，回退一阶段；否则不动（避免误退已推进的订单）。
  def revert_production_order_stage_on_void(timestamp)
    return if production_order.nil?

    # 外购按单：收货过账时从「采购」直推「成品入库」（短脊柱），作废须对称退回「采购」。
    if production_order.is_outsourced && purpose == 'MATERIAL_RECEIPT' && production_order.stage == 'FG_INBOUND'
      others = account.mes_stock_entries
                      .where(production_order_id: production_order_id, purpose: 'MATERIAL_RECEIPT', status: 'POSTED')
                      .where.not(id: id).exists?
      return if others

      production_order.update_columns(status: 'IN_PROGRESS', updated_at: timestamp) if production_order.status == 'COMPLETED'
      return production_order.enter_stage!('PURCHASING', at: timestamp)
    end

    from_stage, to_stage = STAGE_ADVANCE[purpose]
    return if from_stage.nil?
    return if production_order.stage != to_stage

    others_posted = account.mes_stock_entries
                           .where(production_order_id: production_order_id, purpose: purpose, status: 'POSTED')
                           .where.not(id: id).exists?
    return if others_posted

    # 完工入库作废回退：把「生产完成」退回「进行中」，与 fg_inbound 收齐标记对称。
    if purpose == 'MANUFACTURE' && production_order.status == 'COMPLETED'
      production_order.update_columns(status: 'IN_PROGRESS',
                                      updated_at: timestamp)
    end
    production_order.enter_stage!(from_stage, at: timestamp)
  end

  def direction_sign
    IN_PURPOSES.include?(purpose) ? 1 : -1
  end

  # 转换单一单两行、方向相反，所以符号要按行算，不能按单算。其余 purpose 整单同向。
  # 委外产品入库同理：产出品行进仓(+)，倒冲料行出仓(-)。
  def line_sign(item)
    return item.item_type == 'PRODUCT' ? 1 : -1 if purpose == BACKFLUSH_PURPOSE
    return direction_sign unless CONVERT_PURPOSES.include?(purpose)

    gains = purpose == 'CONVERT_TO_PRODUCT' ? 'PRODUCT' : 'MATERIAL'
    item.item_type == gains ? 1 : -1
  end

  def transfer? = TRANSFER_PURPOSES.include?(purpose)

  def default_warehouse_id
    IN_PURPOSES.include?(purpose) ? to_warehouse_id : from_warehouse_id
  end

  # 过账按 purpose 推进关联生产订单阶段（仅当处于前置阶段，避免回退/越级）。
  STAGE_ADVANCE = {
    'MATERIAL_RECEIPT' => %w[PURCHASING MATERIAL_INBOUND],
    'MATERIAL_ISSUE' => %w[MATERIAL_INBOUND PICKING],
    'MANUFACTURE' => %w[PRODUCTION FG_INBOUND],
    'SHIPMENT' => %w[FG_INBOUND SHIPPED]
  }.freeze

  def advance_production_order_on_receipt(timestamp)
    from_stage, to_stage = STAGE_ADVANCE[purpose]
    return if from_stage.nil? || production_order.nil?

    # 外购按单：成品到货收货（MATERIAL_RECEIPT）从「采购」直推「成品入库」，
    # 跳过原料入库/领料/报工（短版脊柱）。外购单条脊柱，不受齐套闸约束。
    if production_order.is_outsourced && purpose == 'MATERIAL_RECEIPT' && production_order.stage == 'PURCHASING'
      return production_order.enter_stage!('FG_INBOUND', at: timestamp)
    end

    # ⚠️ 领料（MATERIAL_ISSUE）不能要求「正好在原料入库阶段」。
    # 2026-11-10 把领料闸从「原料入库」降到「采购原料」之后，车间可以在采购阶段就领料了
    # （料早到仓库、单子还挂在采购中是常态），但这里仍然卡着 stage == MATERIAL_INBOUND，
    # 于是领了料阶段不推进 → 永远到不了 PICKING → **报工彻底做不了**。
    # 改成「还没走到目标阶段就推上去」：领料本身就是开工的信号。
    if purpose == 'MATERIAL_ISSUE'
      return if production_order.stage_reached?(to_stage)
    else
      return if production_order.stage != from_stage
    end

    # 齐套闸：采购原料→原料入库，需本单所有关联采购单都到料齐（一单多采购单主料/辅料分采购）。
    # 未齐套则先按料到料回写、订单留在「采购原料」，等最后一张采购单到齐才推进。
    return if purpose == 'MATERIAL_RECEIPT' && !production_order.purchase_complete?

    production_order.enter_stage!(to_stage, at: timestamp)
  end

  # 完工入库收齐 → 标记「生产完成·待出库」，成品入库阶段即显示完成（不必等出库）。
  # 独立于阶段推进：分批入库时订单已在成品入库阶段，仍要在最后一批收齐时标记完成。
  def complete_production_order_if_fg_full(timestamp)
    return unless purpose == 'MANUFACTURE'

    po = production_order
    return if po.nil? || po.status != 'IN_PROGRESS'
    return unless po.stage == 'FG_INBOUND' && po.fg_inbound_complete?

    po.update_columns(status: 'COMPLETED', updated_at: timestamp)
    finish_stock_order(po)
  end

  # 备货单到这里就是走完了——没有「销售出库」那一步（见 ProductionOrder.spine_for）。
  # 定制单的收尾动作挂在进 SHIPPED 时（on_stage_changed），备货单到不了那里，
  # 不补这一下的话：残留待办销不掉（人家待办里一直挂着「待接单：成品入库」），
  # 成本也归集不进 ERP。
  def finish_stock_order(production_order)
    return unless production_order.stock? && production_order.at_final_stage?

    production_order.resolve_open_todos
    production_order.rollup_erp_cost
  end

  # 成品出库过账 → 订单已发货交付，置「已完成」（SHIPPED 为终态，退出「进行中」）。
  # 兜底直接出库（未经成品入库收齐标记）的订单：出库后仍卡在 IN_PROGRESS 的问题。
  def complete_production_order_if_shipped(timestamp)
    return unless purpose == 'SHIPMENT'

    po = production_order
    return if po.nil? || po.status != 'IN_PROGRESS'
    return unless po.stage == 'SHIPPED'

    po.update_columns(status: 'COMPLETED', updated_at: timestamp)
  end

  # 原料入库过账：按物料把本次收货量累加回采购单明细 received_qty、回填实际到料日期，并重算收货状态。
  # 修复历史遗留（received_qty 从不回写，导致「按采购单收货」剩余量预填失效）+ 支撑齐套判定。
  # 实际到料 = 本次入库日期（首次到料自动填，分批到料覆盖为最近一次；采购员仍可在采购单上手动改）。
  # 本次到料日期：入库单填了实际入库日就用它，否则用过账当下。
  def receipt_arrival_at = actual_inbound_date || Time.current

  # 关联采购单必须审批通过才能收货，杜绝未审批/被驳回的采购单被越权收货推进流程。
  # 追加的那几张也要查：只看主单的话，没批的单能借一张已批的主单把货收进来。
  def ensure_purchase_orders_approved!
    return unless purpose == 'MATERIAL_RECEIPT'

    unapproved = related_purchase_orders.reject(&:approved?)
    return if unapproved.empty?

    raise StandardError, "关联采购单 #{unapproved.map(&:po_no).join('、')} 未审批通过，不能收货"
  end

  # 回写要覆盖**本单关联的每一张采购单**（主单 + 追加的）。
  # 只认主单的话，追加那张单的料收了也不记账：received_qty 不涨、收货状态永远「未收」、
  # 在途量不冲减，下次建入库单这些料还会被当成没收完再铺一遍。
  # 采购单到货量的加减，过账和作废走同一个口子、方向相反。
  #   原料入库：过账 +到货，作废 −到货
  #   采购退货：过账 −到货，作废 +到货（退回去的货又算回来了）
  # 不对称就会出现「退了货采购单还显示已到料」——齐套和到货明细跟着一起错。
  def apply_purchase_receipt(posting:)
    return if purchase_order_id.blank?

    adds = (purpose == 'MATERIAL_RECEIPT') == posting
    case purpose
    when 'MATERIAL_RECEIPT', 'PURCHASE_RETURN' then adds ? sync_purchase_receipt! : reverse_purchase_receipt!
    end
  end

  def sync_purchase_receipt!
    arrival = receipt_arrival_at
    orders = related_purchase_orders.to_a
    stock_entry_items.each do |item|
      po, po_item = locate_purchase_item(orders, item)
      next if po_item.nil?

      po_item.update_columns(
        received_qty: po_item.received_qty.to_d + item.effective_qty,
        arrival_date: arrival
      )
      # 到货冲减采购单在途（已订购未到货）量——收多少冲多少（仅审批通过、累加过在途的单）。
      next unless po.approved?

      po.reduce_on_order_for(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, qty: item.effective_qty
      )
    end
    orders.each { |o| o.reload.recompute_receipt_status! }
  end

  # 同一颗料可能在好几张关联采购单上都有（主料辅料分单下的）。
  # 优先回写「还没收完」的那张——否则收货量全记到已经收满的单上，
  # 真正欠货的那张永远显示没到货。
  def locate_purchase_item(orders, item)
    matches = orders.filter_map do |po|
      hit = po.purchase_items.find { |pi| same_material?(pi, item) }
      [po, hit] if hit
    end
    matches.find { |(_po, pi)| pi.qty.to_d > pi.received_qty.to_d } || matches.first || [nil, nil]
  end

  def same_material?(purchase_item, entry_item)
    (entry_item.mes_material_id && purchase_item.mes_material_id == entry_item.mes_material_id) ||
      (entry_item.crm_product_id && purchase_item.crm_product_id == entry_item.crm_product_id)
  end

  # 作废原料入库的对称冲销：把本单收货量从采购明细 received_qty 扣回（下限 0），
  # 并把在途量补回（reduce_on_order_for 传负数 = 回加在途），最后重算采购收货状态。
  def reverse_purchase_receipt!
    po = purchase_order
    stock_entry_items.each do |item|
      po_item = po.purchase_items.find do |pi|
        (item.mes_material_id && pi.mes_material_id == item.mes_material_id) ||
          (item.crm_product_id && pi.crm_product_id == item.crm_product_id)
      end
      next if po_item.nil?

      po_item.update_columns(received_qty: [po_item.received_qty.to_d - item.effective_qty, 0].max)
      next unless po.approved?

      po.reduce_on_order_for(
        item_type: item.item_type, mes_material_id: item.mes_material_id,
        crm_product_id: item.crm_product_id, qty: -item.effective_qty
      )
    end
    po.reload.recompute_receipt_status!
  end
end
