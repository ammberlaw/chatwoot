# 委外加工单的用料明细。建单时从生产任务单的 BOM 带过来，可改。
#
# 分子/分母/损耗率照搬金蝶口径：
#   标准用量 = 产出数量 × (分子 ÷ 分母) × (1 + 损耗率%)
# 为什么不是直接填一个用量：同一颗料在不同产出规格下用量不同，BOM 记的就是比例；
# 而损耗是委外特有的——料发出去就不在自己眼皮底下，谈的时候就要把损耗算进发料量。
# == Schema Information
#
# Table name: mes_outsource_materials
#
#  id                 :bigint           not null, primary key
#  loss_rate          :decimal(6, 2)    default(0.0), not null
#  qty_denominator    :decimal(16, 6)   default(1.0), not null
#  qty_numerator      :decimal(16, 6)   default(1.0), not null
#  remark             :text
#  std_qty            :decimal(16, 3)   default(0.0), not null
#  unit               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_product_id     :bigint
#  from_warehouse_id  :bigint
#  mes_material_id    :bigint
#  outsource_order_id :bigint           not null
#
# Indexes
#
#  index_mes_outsource_materials_on_account_id          (account_id)
#  index_mes_outsource_materials_on_outsource_order_id  (outsource_order_id)
#
class Mes::OutsourceMaterial < ApplicationRecord
  belongs_to :account
  belongs_to :outsource_order, class_name: 'Mes::OutsourceOrder'
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :from_warehouse, class_name: 'Mes::Warehouse', optional: true

  validate :material_or_product_present

  # 标准用量每次保存都重算。只靠加工单那边「产出数量变了才刷」是不够的——
  # 改这一行自己的分子/分母/损耗率时，加工单的 qty 没动，刷不到这一行
  # （实测把损耗率改成 50%，标准用量还停在原来的 120）。
  before_save :stamp_std_qty

  def display_name = mes_material&.name || crm_product&.name

  def item_code = mes_material&.material_no || crm_product&.sku

  # 标准用量。产出数量变了要跟着重算，所以每次保存前刷一遍（存一份是为了列表和导出不用逐行算）。
  def recompute_std_qty!
    update_column(:std_qty, computed_std_qty) # rubocop:disable Rails/SkipsModelValidations
  end

  def computed_std_qty
    denom = qty_denominator.to_d
    return 0 if denom.zero?

    (outsource_order.qty.to_d * qty_numerator.to_d / denom * (1 + (loss_rate.to_d / 100))).round(3)
  end

  private

  def stamp_std_qty
    self.std_qty = computed_std_qty
  end

  def material_or_product_present
    return if mes_material_id.present? || crm_product_id.present?

    errors.add(:base, '用料行要么挂物料档、要么挂商品档')
  end
end
