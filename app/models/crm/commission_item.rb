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

  private

  def inherit_account
    self.account_id ||= sheet&.account_id
  end
end
