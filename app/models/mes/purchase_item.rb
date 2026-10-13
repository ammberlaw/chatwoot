# == Schema Information
#
# Table name: mes_purchase_items
#
#  id                 :bigint           not null, primary key
#  amount_micros      :bigint
#  arrival_date       :datetime
#  aux_attribute_name :string
#  item_type          :string           default("MATERIAL"), not null
#  price_tax_included :boolean          default(FALSE), not null
#  qty                :decimal(14, 3)   not null
#  rate_micros        :bigint
#  received_qty       :decimal(14, 3)   default(0.0), not null
#  remark             :text
#  supplier_seq       :integer
#  unit               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_product_id     :bigint
#  mes_material_id    :bigint
#  mes_supplier_id    :bigint
#  purchase_order_id  :bigint           not null
#
# Indexes
#
#  index_mes_purchase_items_on_account_id         (account_id)
#  index_mes_purchase_items_on_crm_product_id     (crm_product_id)
#  index_mes_purchase_items_on_mes_material_id    (mes_material_id)
#  index_mes_purchase_items_on_mes_supplier_id    (mes_supplier_id)
#  index_mes_purchase_items_on_po_supplier_seq    (purchase_order_id,mes_supplier_id,supplier_seq)
#  index_mes_purchase_items_on_purchase_order_id  (purchase_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (mes_supplier_id => mes_suppliers.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => cascade
#
class Mes::PurchaseItem < ApplicationRecord
  # MATERIAL=生产用料（挂 mes_material）；PRODUCT=外购成品（挂 crm_product，不经过生产部）。
  ITEM_TYPES = %w[MATERIAL PRODUCT].freeze

  belongs_to :account
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', inverse_of: :purchase_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true
  # 行内附图（只对内）：这颗料的样品照 / 来料照 / 跟供应商确认的截图。
  # ⚠️ 不进发给供应商的采购订单——导出那份是 PoTemplateFiller 按公司 Excel 模板填的
  # 固定表格、供应商预览组件 MesPoSupplierDoc 也只渲染固定几列，两边都不读这里。
  # 赋值语义是**整组替换**（Rails 7.1 的 has_many_attached=，见 CreateMany/DeleteMany）：
  # 前端每次提交这一行当前应有的完整 signed_id 列表，删掉的自然就没了。
  has_many_attached :images

  before_validation :inherit_account, :compute_amount
  after_destroy :sync_total
  after_save :sync_total

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :qty, presence: true, numericality: { greater_than: 0 }

  # 供应商税率（百分数，如 13 表示 13%），在供应商档案设置、采购单自动带出。
  # 用于含税/未税单价换算与对供应商导出抬头口径。
  def supplier_tax_rate = mes_supplier&.tax_rate.to_d

  # 未税单价（micros）：录入价按未税存则直接返回，按含税存则反算 rate ÷ (1 + 税率%)。
  def untaxed_rate_micros
    r = rate_micros.to_d
    return r unless price_tax_included && supplier_tax_rate.positive?

    (r / (1 + supplier_tax_rate / 100)).round
  end

  # 含税单价（micros）：录入价按含税存则直接返回，按未税存则加税 rate × (1 + 税率%)。
  def taxed_rate_micros
    r = rate_micros.to_d
    return r if price_tax_included || !supplier_tax_rate.positive?

    (r * (1 + supplier_tax_rate / 100)).round
  end

  # 未税 / 含税合计（micros）：单价各按各的口径乘数量。
  # amount_micros 存的是「按录入口径」的金额（含税录入就是含税额），列表上单看一个数
  # 分不清是哪种，对账时就对不上——所以两个都摆出来。
  def untaxed_amount_micros = (qty.to_d * untaxed_rate_micros).round

  def taxed_amount_micros = (qty.to_d * taxed_rate_micros).round

  private

  def inherit_account
    self.account_id ||= purchase_order&.account_id
  end

  def compute_amount
    self.amount_micros = ((qty || 0).to_d * (rate_micros || 0)).round
  end

  def sync_total
    purchase_order.recompute_total!
    # 追加/删除/改量后重算收货齐套状态，避免收齐后追加明细仍误判 RECEIVED → 越级开料。
    purchase_order.recompute_receipt_status!
  end
end
