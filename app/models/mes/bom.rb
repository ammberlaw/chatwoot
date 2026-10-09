# == Schema Information
#
# Table name: mes_boms
#
#  id                         :bigint           not null, primary key
#  bare_color                 :string
#  base_qty                   :decimal(14, 3)   default(1.0), not null
#  bom_no                     :string           not null
#  case_color                 :string
#  customer_name              :string
#  doc_no                     :string
#  estimated_lead_days        :integer
#  fg_inbound_days            :integer
#  is_active                  :boolean          default(TRUE), not null
#  is_default                 :boolean          default(FALSE), not null
#  material_inbound_days      :integer
#  model                      :string
#  order_qty                  :integer
#  picking_days               :integer
#  product_code               :string
#  product_line               :string
#  production_days            :integer
#  purchasing_days            :integer
#  remark                     :text
#  status                     :string           default("DRAFT"), not null
#  submit_date                :date
#  total_material_cost_micros :bigint
#  unit                       :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  crm_product_id             :bigint
#  owner_id                   :bigint
#  sales_owner_id             :bigint
#
# Indexes
#
#  index_mes_boms_on_account_and_product_line  (account_id,product_line)
#  index_mes_boms_on_account_id                (account_id)
#  index_mes_boms_on_account_id_and_bom_no     (account_id,bom_no) UNIQUE
#  index_mes_boms_on_account_id_and_status     (account_id,status)
#  index_mes_boms_on_crm_product_id            (crm_product_id)
#  index_mes_boms_on_owner_id                  (owner_id)
#  index_mes_boms_on_sales_owner_id            (sales_owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (sales_owner_id => users.id) ON DELETE => nullify
#
class Mes::Bom < ApplicationRecord
  include Mes::DocumentNumber
  include Mes::LineScoped
  require_product_line!

  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :owner, class_name: 'User', optional: true # 负责人：起草本生产任务单的工程/PMC 账号
  belongs_to :sales_owner, class_name: 'User', optional: true # 订单归属业务员
  has_many :bom_items, class_name: 'Mes::BomItem', dependent: :destroy, inverse_of: :bom
  has_many :bom_revisions, class_name: 'Mes::BomRevision', dependent: :destroy, inverse_of: :bom
  has_many :production_orders, class_name: 'Mes::ProductionOrder', dependent: :nullify
  accepts_nested_attributes_for :bom_items, allow_destroy: true
  has_many_attached :images # 结构图/样品图（缩略展示）
  has_many_attached :logos  # 客户 logo（印在产品上的标，和结构图不是一回事，混在一起分不清）
  has_many_attached :files  # 附件（工艺文档/图纸等）

  # 按阶段预估天数（工程/PMC 分部门填），求和 = 预计生产周期（不含销售出库/物流）。
  LEAD_DAY_COLUMNS = %i[purchasing_days material_inbound_days picking_days production_days fg_inbound_days].freeze

  # 草稿/下发：草稿可反复编辑、对下游隐藏；下发后才可被生产订单挂用。
  STATUSES = %w[DRAFT RELEASED].freeze

  validates :bom_no, presence: true, uniqueness: { scope: :account_id }
  validates :base_qty, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  # 生产任务单上补了成品之后，把它带到挂着本单的生产订单上。
  # 挂 BOM 与填成品不一定同时发生（工程常先挂单、过后才补产成品代码），
  # 只有 attach_bom! 那一个入口的话，后补的永远传不下去——生产订单那列一直是「—」，
  # 销售订单更拿不到（回填是从生产订单往下走的）。
  after_commit :backfill_production_orders_product, on: %i[create update]

  scope :active, -> { where(is_active: true) }
  scope :released, -> { where(status: 'RELEASED') }

  def released? = status == 'RELEASED'
  def draft? = status == 'DRAFT'

  def self.document_number_prefix = 'BOM'
  def self.document_number_column = :bom_no

  # 各阶段预估天数求和；无填写则回退旧的整体预估交期。
  def total_lead_days
    sum = LEAD_DAY_COLUMNS.sum { |col| public_send(col).to_i }
    sum.positive? ? sum : estimated_lead_days.to_i
  end

  # 用料明细的实时库存映射：料号(material_no) → 该物料各仓实时结存合计。
  # 物料档案统一走产品档案（料号=产品 SKU），故按 SKU 对上产品再汇总 StockBalance。
  # 对不上产品档案的料号取 0（无库存记录）。供 BOM 明细/采购算料展示「对应物料实时库存」。
  def onhand_by_material_no
    codes = bom_items.filter_map(&:material_no).uniq
    return {} if codes.empty?

    sku_to_pid = Crm::Product.where(account_id: account_id, sku: codes).pluck(:sku, :id).to_h
    onhand = Mes::StockBalance.where(account_id: account_id, crm_product_id: sku_to_pid.values)
                              .group(:crm_product_id).sum(:qty)
    sku_to_pid.transform_values { |pid| onhand[pid] || 0 }
  end

  # 行上要显示的产品档案信息（按料号↔SKU 对上）：档案备注 + 该物料启用中的辅助属性。
  # 档案备注是工程写死在产品上的工艺要求（如「外露线长90mm」），录单和车间都得看见；
  # 辅助属性选项要跟着回来，否则重开编辑时下拉是空的、已选的属性显示成「—」。
  def product_info_by_material_no
    codes = bom_items.filter_map(&:material_no).uniq
    return {} if codes.empty?

    Crm::Product.where(account_id: account_id, sku: codes)
                .includes(:aux_attributes)
                .index_by(&:sku)
  end

  # 用料快照（供变更前后对比）：按料号（无料号退料名）归一。
  def items_snapshot
    bom_items.map do |i|
      { key: (i.material_no.presence || "名:#{i.material_name}"),
        material_no: i.material_no, material_name: i.material_name,
        qty: i.qty.to_d, unit: i.unit }
    end
  end

  # 对比两份快照，返回变更明细数组（新增/删除/改量）。无实质变更则空数组。
  def self.diff_items(before, after)
    before_by = before.index_by { |r| r[:key] }
    after_by = after.index_by { |r| r[:key] }
    changes = []
    (after_by.keys - before_by.keys).each do |k|
      r = after_by[k]
      changes << { kind: 'added', material_no: r[:material_no], material_name: r[:material_name], to_qty: r[:qty].to_s, unit: r[:unit] }
    end
    (before_by.keys - after_by.keys).each do |k|
      r = before_by[k]
      changes << { kind: 'removed', material_no: r[:material_no], material_name: r[:material_name], from_qty: r[:qty].to_s, unit: r[:unit] }
    end
    (before_by.keys & after_by.keys).each do |k|
      b = before_by[k]
      a = after_by[k]
      next if b[:qty] == a[:qty]

      changes << { kind: 'changed', material_no: a[:material_no], material_name: a[:material_name],
                   from_qty: b[:qty].to_s, to_qty: a[:qty].to_s, unit: a[:unit] }
    end
    changes
  end

  # 变更摘要（通知正文/时间线用）：+新增料 / -删除料 / 用量 A→B。
  def self.diff_summary(changes)
    changes.map do |c|
      label = c[:material_name].presence || c[:material_no]
      case c[:kind]
      when 'added' then "+#{label} #{c[:to_qty]}#{c[:unit]}"
      when 'removed' then "-#{label}"
      else "#{label} #{c[:from_qty]}→#{c[:to_qty]}#{c[:unit]}"
      end
    end.join('；')
  end

  private

  # 成品没变就不折腾；只补还没有编码的生产订单（人工选过的不动）。
  # 回填失败不该把生产任务单的保存一起回滚，异常只记日志。
  def backfill_production_orders_product
    return unless previous_changes.key?('crm_product_id') || previous_changes.key?('product_code')

    production_orders.where(crm_product_id: nil).find_each do |order|
      order.backfill_product_from_bom(self)
    end
  rescue StandardError => e
    Rails.logger.error("[Mes::Bom] #{bom_no} 回填生产订单商品编码失败: #{e.class} #{e.message}")
  end

  def product_line_source = crm_product
end
