# 提成表明细行：一行一笔订单。自动带出时关联来源销售订单，业务员再补运费/汇率/到款等。
# 金额一律整数微分（×1_000_000）存储；产品品类用于导出/展示时分组小计。
# == Schema Information
#
# Table name: crm_commission_items
#
#  id                      :bigint           not null, primary key
#  country                 :string
#  currency                :string           default("USD")
#  customer_name           :string
#  exchange_rate           :decimal(12, 6)
#  is_public_receipt       :boolean          default(FALSE), not null
#  order_amount_micros     :bigint
#  order_no                :string
#  payment_channel         :string
#  payment_date            :datetime
#  position                :integer          default(0)
#  product                 :string
#  product_category        :string
#  received_amount_micros  :bigint
#  received_rmb_micros     :bigint
#  remark                  :text
#  sales_rmb_micros        :bigint
#  shipping_micros         :bigint
#  tax_rate                :integer          default(13), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  crm_commission_sheet_id :bigint           not null
#  crm_sales_order_id      :bigint
#
# Indexes
#
#  index_crm_commission_items_on_account_id               (account_id)
#  index_crm_commission_items_on_crm_commission_sheet_id  (crm_commission_sheet_id)
#  index_crm_commission_items_on_crm_sales_order_id       (crm_sales_order_id)
#
class Crm::CommissionItem < ApplicationRecord
  belongs_to :account
  belongs_to :sheet, class_name: 'Crm::CommissionSheet',
             foreign_key: :crm_commission_sheet_id, inverse_of: :items
  belongs_to :sales_order, class_name: 'Crm::SalesOrder',
             foreign_key: :crm_sales_order_id, optional: true

  before_validation :inherit_account, on: :create

  # 对公时可选的增值税点（每行手选）；默认 13。
  TAX_RATES = [13, 11].freeze

  # 提成基数（微分）：对公则销售额RMB ÷(1+税点%)，否则即销售额RMB。销售额RMB 未填则为 nil。
  def commission_base_micros
    return nil if sales_rmb_micros.nil?

    base = sales_rmb_micros.to_i
    return base unless is_public_receipt

    (base / (1 + tax_rate.to_f / 100)).round
  end

  # 提成工资（微分）= 提成基数 × 提成点% / 100。基数空或点位为 0 则为 nil。
  def commission_salary_micros(rate)
    base = commission_base_micros
    r = rate.to_f
    return nil if base.nil? || r.zero?

    (base * r / 100.0).round
  end

  private

  def inherit_account
    self.account_id ||= sheet&.account_id
  end
end
