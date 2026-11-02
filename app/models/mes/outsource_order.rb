# 委外加工单。把自己的料发给加工厂，加工厂做好还回来，我们按件付加工费。
#
# 与「外购」(mes_production_orders.is_outsourced) 的分界：
#   外购＝整台成品买进来，料和过程都不是我们的，走采购收货直入成品仓；
#   委外＝**料还是我们的**，只是换个地方加工，所以料必须跟着单据在委外仓记一笔。
#
# 四张单的关系（与金蝶一致）：
#   委外加工单（本表，主单）
#     ├─ 委外发料单   原料仓 → 委外仓（purpose=OUTSOURCE_ISSUE）
#     ├─ 委外产品入库单 产出入成品仓 + 按标准用量倒冲委外仓的料（OUTSOURCE_RECEIPT）
#     └─ 委外退料单   委外仓 → 原料仓/不良品仓（OUTSOURCE_RETURN）
#
# 加工费按**件**计价（金蝶单上 48.00 未税 / 52.80 含税 / 税率 10），不是整单包干；
# 应付在产品入库过账时按实收数量挂（见 Mes::StockEntry）。
# == Schema Information
#
# Table name: mes_outsource_orders
#
#  id                  :bigint           not null, primary key
#  delivery_date       :date
#  doc_date            :date             not null
#  fee_rate_micros     :bigint           default(0), not null
#  fee_tax_included    :boolean          default(FALSE), not null
#  order_no            :string           not null
#  product_line        :string
#  qty                 :decimal(16, 3)   default(0.0), not null
#  remark              :text
#  status              :string           default("DRAFT"), not null
#  tax_rate            :decimal(6, 2)    default(0.0), not null
#  unit                :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_product_id      :bigint           not null
#  mes_supplier_id     :bigint           not null
#  mes_warehouse_id    :bigint
#  owner_id            :bigint
#  production_order_id :bigint
#  to_warehouse_id     :bigint
#
# Indexes
#
#  index_mes_outsource_orders_on_account_id_and_order_no      (account_id,order_no) UNIQUE
#  index_mes_outsource_orders_on_account_id_and_product_line  (account_id,product_line)
#  index_mes_outsource_orders_on_account_id_and_status        (account_id,status)
#  index_mes_outsource_orders_on_mes_supplier_id              (mes_supplier_id)
#  index_mes_outsource_orders_on_production_order_id          (production_order_id)
#
class Mes::OutsourceOrder < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  require_product_line!

  # DRAFT 草稿 → CONFIRMED 已确认（可发料/入库）→ CLOSED 关闭（不再收料）
  STATUSES = %w[DRAFT CONFIRMED CLOSED CANCELLED].freeze

  belongs_to :account
  belongs_to :production_order, class_name: 'Mes::ProductionOrder', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier'
  belongs_to :crm_product, class_name: 'Crm::Product'
  belongs_to :mes_warehouse, class_name: 'Mes::Warehouse', optional: true # 委外仓
  belongs_to :to_warehouse, class_name: 'Mes::Warehouse', optional: true  # 产出入库仓
  belongs_to :owner, class_name: 'User', optional: true

  has_many :outsource_materials, class_name: 'Mes::OutsourceMaterial',
                                 dependent: :destroy, inverse_of: :outsource_order
  # 草稿单跟着加工单一起删，已过账的不许删（它们动过库存）。
  # 原来写 dependent: :nullify，删完加工单那些草稿变成 outsource_order_id 为空的孤儿：
  # 委外页上看不到、原料入库那几页也不收这个 purpose，谁都管不了，却还能被过账。
  has_many :stock_entries, class_name: 'Mes::StockEntry', dependent: :destroy
  accepts_nested_attributes_for :outsource_materials, allow_destroy: true

  validates :order_no, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :qty, numericality: { greater_than: 0 }

  # prepend: true 必须加——has_many 的 dependent: :destroy 也是注册成 before_destroy 的，
  # 而且注册在前。不 prepend 的话子单据先被删光，轮到这个守卫时「已过账的」已经一条不剩，
  # 守卫永远放行（实测把一张有已过账发料单的加工单直接删掉了）。
  before_destroy :ensure_no_posted_entries, prepend: true
  after_save :refresh_material_std_qty

  def self.document_number_prefix = 'WW'

  scope :open_orders, -> { where(status: %w[DRAFT CONFIRMED]) }

  # 加工费未税单价。录的是含税价时按税率倒算，口径同采购单的含税/未税换算。
  def fee_rate_untaxed_micros
    return fee_rate_micros unless fee_tax_included

    (fee_rate_micros / (1 + (tax_rate.to_d / 100))).round
  end

  def fee_rate_taxed_micros
    return fee_rate_micros if fee_tax_included

    (fee_rate_micros * (1 + (tax_rate.to_d / 100))).round
  end

  # 这张单已经发出去多少 / 已经收回来多少 / 已经退回来多少（都只认已过账）。
  def issued_qty_for(material)
    posted_item_qty('OUTSOURCE_ISSUE', material)
  end

  def returned_qty_for(material)
    posted_item_qty('OUTSOURCE_RETURN', material)
  end

  def received_qty
    posted_entries('OUTSOURCE_RECEIPT')
      .joins(:stock_entry_items)
      .where(mes_stock_entry_items: { crm_product_id: crm_product_id, item_type: 'PRODUCT' })
      .sum('mes_stock_entry_items.qty')
  end

  # 还差多少没收。收满了就不该再开入库单。
  def remaining_qty = [qty.to_d - received_qty.to_d, 0].max

  # 加工厂手上还剩多少这颗料可退 ＝ 已发 − 已被产品入库倒冲掉 − 已退。
  # 金蝶那张退料单上的「供应商剩余可退数量」就是这个数。
  def returnable_qty_for(material)
    [issued_qty_for(material) - backflushed_qty_for(material) - returned_qty_for(material), 0].max
  end

  # 已被倒冲掉的量：产品入库时按标准用量从委外仓扣的那部分。
  def backflushed_qty_for(material)
    posted_entries('OUTSOURCE_RECEIPT')
      .joins(:stock_entry_items)
      .where(mes_stock_entry_items: item_scope(material).merge(item_type: 'MATERIAL'))
      .sum('mes_stock_entry_items.qty')
  end

  private

  def posted_entries(purpose)
    account.mes_stock_entries.where(outsource_order_id: id, purpose: purpose, status: 'POSTED')
  end

  def posted_item_qty(purpose, material)
    posted_entries(purpose).joins(:stock_entry_items)
                           .where(mes_stock_entry_items: item_scope(material))
                           .sum('mes_stock_entry_items.qty')
  end

  def item_scope(material)
    if material.mes_material_id.present?
      { mes_material_id: material.mes_material_id }
    else
      { crm_product_id: material.crm_product_id }
    end
  end

  # 动过库存的单不能跟着加工单一起删——控制器那层已经拦了一道，这里再兜一道：
  # 服务层/控制台也会调 destroy，只在界面上拦不住。
  def ensure_no_posted_entries
    return if stock_entries.where(status: 'POSTED').none?

    errors.add(:base, '这张加工单下有已过账的单据，不能删；请先作废那些单据，或把加工单关闭')
    throw :abort
  end

  # 产出数量改了，所有用料行的标准用量要跟着重算。
  def refresh_material_std_qty
    return unless saved_change_to_qty?

    outsource_materials.each(&:recompute_std_qty!)
  end
end
