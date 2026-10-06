# 订单成本归集行：一张销售订单可以挂多条成本（材料/加工/运费/佣金/其他）。
# 毛利 = 订单收入 - Σ成本（实时算，不落库；见 ERP_SPEC §4.2）。
# ⚠️ 权限墙核心区：成本与毛利只在 ERP 内可见，CRM/MES 的任何接口都不得输出。
# == Schema Information
#
# Table name: erp_order_costs
#
#  id                 :bigint           not null, primary key
#  amount_micros      :bigint           not null
#  cost_type          :string           default("MATERIAL"), not null
#  currency           :string           default("CNY"), not null
#  exchange_rate      :decimal(12, 6)   default(1.0), not null
#  happened_at        :date
#  remark             :text
#  source_type        :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#  crm_sales_order_id :bigint           not null
#  mes_supplier_id    :bigint
#  source_id          :bigint
#
# Indexes
#
#  index_erp_order_costs_on_account_id                (account_id)
#  index_erp_order_costs_on_account_id_and_cost_type  (account_id,cost_type)
#  index_erp_order_costs_on_crm_sales_order_id        (crm_sales_order_id)
#  index_erp_order_costs_on_source                    (account_id,source_type,source_id) UNIQUE WHERE (source_type IS NOT NULL)
#
class Erp::OrderCost < ApplicationRecord

  # 跨币种求和必须折本位币（成本行带 currency/exchange_rate）。
  # 命名与 Receivable/Payable 等保持一致，守卫 spec 按这个前缀认。
  BASE_AMOUNT_MICROS_SQL = 'ROUND(erp_order_costs.amount_micros * COALESCE(erp_order_costs.exchange_rate, 1))'.freeze
  COST_TYPES = %w[MATERIAL PROCESS FREIGHT COMMISSION EXPENSE OTHER].freeze
  COST_TYPE_LABELS = {
    'MATERIAL' => '材料成本', 'PROCESS' => '加工/外协', 'FREIGHT' => '运费',
    'COMMISSION' => '佣金', 'EXPENSE' => '报销费用', 'OTHER' => '其他'
  }.freeze

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder'
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  validates :cost_type, inclusion: { in: COST_TYPES }
  validates :amount_micros, numericality: { greater_than: 0 }

  def base_amount_micros
    (amount_micros * exchange_rate).round
  end
end
