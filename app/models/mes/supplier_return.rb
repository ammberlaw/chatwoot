# 退料返修单：把料退给供应商修，修好再回来。
#
# 用户原话：「我这边退料出去，多久能回来？是不是要设置一个退出去的时间跟物料返修回来时间呢」
# 所以这张单的重点不是数量，是**两个时间**和中间这段在外面的天数。
#
# ⚠️ 本期只记台账、不动库存：返修回来要不要重新入库、要不要质检还没定（用户标「待确认」）。
# 真要接库存时，按明细行补入库单即可——行上已经记了产品档案 id 和已返回数量。
# == Schema Information
#
# Table name: mes_supplier_returns
#
#  id                    :bigint           not null, primary key
#  posted_at             :datetime
#  product_line          :string
#  reason                :text
#  remark                :text
#  return_kind           :string           default("REPLACE"), not null
#  return_no             :string           not null
#  returned_on           :date
#  sent_on               :date
#  status                :string           default("DRAFT"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  mes_purchase_order_id :bigint
#  mes_supplier_id       :bigint           not null
#  out_stock_entry_id    :bigint
#  owner_id              :bigint
#  production_order_id   :bigint
#  source_stock_entry_id :bigint
#  warehouse_id          :bigint
#
# Indexes
#
#  index_mes_supplier_returns_on_account_id_and_return_kind  (account_id,return_kind)
#  index_mes_supplier_returns_on_account_id_and_return_no    (account_id,return_no) UNIQUE
#  index_mes_supplier_returns_on_account_id_and_status       (account_id,status)
#  index_mes_supplier_returns_on_mes_purchase_order_id       (mes_purchase_order_id)
#  index_mes_supplier_returns_on_production_order_id         (production_order_id)
#
class Mes::SupplierReturn < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped

  STATUS_LABELS = {
    'DRAFT' => '草稿',
    'SENT' => '已退出',
    'PARTIAL' => '部分返回',
    'RETURNED' => '已返回',
    'CLOSED' => '已关闭'
  }.freeze
  STATUSES = STATUS_LABELS.keys.freeze

  # 退回去换新的 / 退掉不要了——财务口径的分叉（2026-10-29 用户定）。
  #
  # 落到实现上不是两套流程，而是**过账生成的那张 PURCHASE_RETURN 库存单带不带采购单号**：
  #   REPLACE 不带 → Mes::StockEntry#apply_purchase_receipt 开头就 return（没有采购单），
  #                  Erp::AutoVoucherService#stock_receipt_rows 也取不到采购行 → 只扣库存。
  #   REFUND  带上 → 冲回采购单到货量 + 应付走红字。
  # 所以这两种的差别全在一个外键上，不需要新 purpose、不需要在库存单上加开关。
  REPLACE = 'REPLACE'.freeze
  REFUND = 'REFUND'.freeze
  RETURN_KINDS = [REPLACE, REFUND].freeze
  RETURN_KIND_LABELS = { REPLACE => '退换', REFUND => '退货' }.freeze

  belongs_to :account
  belongs_to :mes_supplier, class_name: 'Mes::Supplier'
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :warehouse, class_name: 'Mes::Warehouse', optional: true
  belongs_to :mes_purchase_order, class_name: 'Mes::PurchaseOrder', optional: true
  # 货是哪张入库单收进来的 / 退出去时生成的那张出库单。两个都是用户点名要的「关联单号」。
  belongs_to :source_stock_entry, class_name: 'Mes::StockEntry', optional: true
  belongs_to :out_stock_entry, class_name: 'Mes::StockEntry', optional: true
  belongs_to :owner, class_name: 'User', optional: true
  has_many :items, class_name: 'Mes::SupplierReturnItem', dependent: :destroy, inverse_of: :supplier_return
  accepts_nested_attributes_for :items, allow_destroy: true

  validates :return_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :return_kind, inclusion: { in: RETURN_KINDS }
  # 退掉不要了就得说清楚冲哪张采购单的账——不挂采购单的话到货量和应付都冲不了，
  # 单子看着是「退款」，账上却一分钱没动。
  validates :mes_purchase_order_id, presence: { message: '退货必须关联采购单' },
                                    if: -> { return_kind == REFUND }

  before_validation :inherit_account_on_items

  def self.document_number_prefix = 'RT'
  def self.document_number_column = :return_no

  def status_label = STATUS_LABELS[status]

  # 退出去多少天了 / 这趟来回走了多少天——用户要的就是这个数。
  def days_out
    return nil if sent_on.blank?

    ((returned_on || Date.current) - sent_on).to_i
  end

  def out? = sent_on.present? && returned_on.blank?

  def return_kind_label = RETURN_KIND_LABELS[return_kind]
  def refund? = return_kind == REFUND

  # 退出 → 真的从仓库扣货、记日期、进「已退出」。
  #
  # 以前这一步只改两个字段，货还在系统里躺着（这本台账从头到尾不动库存）。
  # 用户要的是「从不良品仓退回供应商」，那就得真扣——否则不良品仓的 183 行结存
  # 永远只进不出。
  def send_out!(on: nil, actor: nil)
    raise StandardError, '这张单已经退出去了' if sent_on.present?
    raise StandardError, '请先填退料明细' if items.empty?
    raise StandardError, '请先选从哪个仓退出' if warehouse_id.blank?

    transaction do
      entry = build_out_entry(actor)
      entry.save!
      entry.post!
      update!(sent_on: on.presence || Date.current, status: 'SENT',
              posted_at: Time.current, out_stock_entry: entry)
    end
    self
  end

  # 登记返回：按行填「这次回来多少」，累加到 returned_qty，再按齐不齐定单据状态，
  # 同时**真的把货入回库**（一次返回一张入库单，分批回来就是几张）。
  #
  # 不入库的话账就是半边的：退出去扣了、回来不加，这颗料在系统里凭空少掉。
  # 入哪个仓由调用方给（换回来的是好货，一般进原料仓，不再回不良品仓）；没给就回原仓。
  #
  # 退掉不要了（REFUND）的单不该有返回——货都不要了还回来什么，拦住。
  def receive_back!(rows, on: nil, warehouse_id: nil, actor: nil)
    raise StandardError, '这张单还没退出去' if sent_on.blank?
    raise StandardError, '退货单不会有返回，请另开退换单' if refund?

    transaction do
      applied = apply_returned_rows(rows)
      raise StandardError, '没有填任何返回数量' if applied.empty?

      receive_entry!(applied, warehouse_id, actor)
      reload
      update!(returned_on: on.presence || Date.current, status: derived_status)
    end
    self
  end

  private

  # 退出去那张库存单。purpose 固定 PURCHASE_RETURN（出库方向、成本侧按采购退货处理），
  # **采购单号只有 REFUND 才挂**——见上面 RETURN_KINDS 那段，这个外键就是两种退法的全部差别。
  def build_out_entry(actor)
    account.mes_stock_entries.new(
      purpose: 'PURCHASE_RETURN',
      status: 'DRAFT',
      owner_id: actor&.id || owner_id,
      from_warehouse_id: warehouse_id,
      purchase_order_id: (mes_purchase_order_id if refund?),
      production_order_id: production_order_id,
      remark: "采购退料 #{return_no}（#{return_kind_label}）",
      stock_entry_items_attributes: items.map do |item|
        { account_id: account_id, item_type: 'MATERIAL', crm_product_id: item.crm_product_id,
          qty: item.qty, warehouse_id: warehouse_id }
      end
    )
  end

  # 累加本次返回量，并把「这次回来了哪几行、各多少」返回给调用方去开入库单。
  # 不能拿 item.returned_qty 当入库量——那是累计数，分批回来会把之前入过的再入一遍。
  def apply_returned_rows(rows)
    Array(rows).filter_map do |row|
      item = items.find_by(id: row[:id] || row['id'])
      next if item.nil?

      qty = (row[:returned_qty] || row['returned_qty']).to_d
      next if qty <= 0

      # 回来的不可能比退出去的多，多填的按还差多少截断，免得入出一个库里没有的数。
      qty = [qty, item.outstanding_qty].min
      next if qty <= 0

      item.update!(returned_qty: item.returned_qty.to_d + qty)
      { item: item, qty: qty }
    end
  end

  # 返回入库：换回来的是好货，默认进原料仓（调用方可改），不再回不良品仓。
  def receive_entry!(applied, warehouse_id, actor)
    target = warehouse_id.presence || self.warehouse_id
    entry = account.mes_stock_entries.new(
      purpose: 'MATERIAL_RECEIPT', status: 'DRAFT',
      owner_id: actor&.id || owner_id, to_warehouse_id: target,
      production_order_id: production_order_id,
      remark: "采购退料 #{return_no} 返修/换货返回",
      stock_entry_items_attributes: applied.map do |row|
        { account_id: account_id, item_type: 'MATERIAL',
          crm_product_id: row[:item].crm_product_id, qty: row[:qty], warehouse_id: target }
      end
    )
    entry.save!
    entry.post!
  end

  # 全部回来了＝已返回；回来一部分＝部分返回；一件没回＝维持已退出。
  def derived_status
    total = items.sum(&:qty).to_d
    back = items.sum(&:returned_qty).to_d
    return 'SENT' if back <= 0
    return 'RETURNED' if back >= total

    'PARTIAL'
  end

  def product_line_source = production_order

  def inherit_account_on_items
    items.each { |item| item.account_id ||= account_id }
  end
end
