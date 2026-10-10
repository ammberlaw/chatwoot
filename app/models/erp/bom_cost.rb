# BOM 成本表：每个商品编码一条标准加工成本（加工费 = 生产人工，制造费用）。
#
# ⚠️ 按**产品档案**（crm_products，商品编码=sku）挂，不是按 Mes::Bom——
# 「BOM 成本表」是用户的叫法，别顺着名字去找 Mes::Bom。
#
# 产品名称/规格型号不在本表存副本：渲染时从产品档案带，改了档案这边自然跟着变。
#
# 用途：成品入库过账后，Erp::CostRollupService 按
#   完工入库数量 × 加工费     → LABOR    成本行
#   完工入库数量 × 制造费用   → OVERHEAD 成本行
# 归集到销售订单上，和领料算出来的 MATERIAL 一起构成毛利的成本侧。
# == Schema Information
#
# Table name: erp_bom_costs
#
#  id                  :bigint           not null, primary key
#  overhead_fee_micros :bigint           default(0), not null
#  process_fee_micros  :bigint           default(0), not null
#  remark              :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  crm_product_id      :bigint           not null
#  updated_by_id       :bigint
#
# Indexes
#
#  idx_erp_bom_costs_on_account_product   (account_id,crm_product_id) UNIQUE
#  index_erp_bom_costs_on_account_id      (account_id)
#  index_erp_bom_costs_on_crm_product_id  (crm_product_id)
#  index_erp_bom_costs_on_updated_by_id   (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => cascade
#  fk_rails_...  (updated_by_id => users.id) ON DELETE => nullify
#
class Erp::BomCost < ApplicationRecord
  belongs_to :account
  belongs_to :crm_product, class_name: 'Crm::Product'
  belongs_to :updated_by, class_name: 'User', optional: true

  # 文案写死中文、不走语言文件：API 请求下 locale 实测解析不到 zh_CN，查出来是英文；
  # 全站业务校验文案（如 Mes::LineScoped 的产品线必填）都是这么写的，保持一致。
  # rubocop:disable Rails/I18nLocaleTexts
  validates :crm_product_id, uniqueness: { scope: :account_id, message: '这个商品编码已经有一条了，直接改那条' }
  # rubocop:enable Rails/I18nLocaleTexts
  validates :process_fee_micros, :overhead_fee_micros,
            numericality: { greater_than_or_equal_to: 0 }

  scope :for_products, ->(ids) { where(crm_product_id: ids) }

  # 单位加工成本合计（人工 + 制造费用）。
  def unit_cost_micros = process_fee_micros.to_i + overhead_fee_micros.to_i
end
