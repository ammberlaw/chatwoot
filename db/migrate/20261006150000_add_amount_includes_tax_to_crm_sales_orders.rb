# 订单金额含不含税：**同一家公司两种都有**（用户 2026-10-06 明确），所以必须落到单据上，
# 账套设置那个只当新建时的默认值。
#   含税：收入 = 金额 ÷ (1+税率)，销项税 = 金额 − 收入，应收 = 金额
#   不含税：收入 = 金额，销项税 = 金额 × 税率，应收 = 金额 + 税额
# 留 NULL = 跟随账套默认；存量不回填，让它们走默认，财务改过哪张哪张就定死。
class AddAmountIncludesTaxToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_sales_orders, :amount_includes_tax, :boolean
  end
end
